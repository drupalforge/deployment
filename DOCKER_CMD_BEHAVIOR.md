# Docker CMD Behavior: USER vs ENTRYPOINT

## The Question

> "You said the `USER` instruction in the Dockerfile unsets `CMD`. Can the Dockerfile read `CMD` before the first user instruction and save it to a variable, then set `CMD` after the last `USER` instruction?"

## The Answer

**Clarification: `USER` does NOT unset `CMD`. It's `ENTRYPOINT` that resets `CMD`.**

## Understanding Docker's Behavior

### Test 1: USER Instruction

```dockerfile
FROM devpanel/php:8.3-base
# Base has: CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh"]

USER root
USER ${USER}
# CMD is STILL inherited from base image ✓
```

**Result**: `docker inspect` shows CMD is preserved: `["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh"]`

### Test 2: ENTRYPOINT Instruction

```dockerfile
FROM devpanel/php:8.3-base
# Base has: CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh"]

ENTRYPOINT ["/custom/entrypoint"]
# CMD is now RESET to null ✗
```

**Result**: `docker inspect` shows CMD is `null`

## Why Can't Dockerfile Read CMD?

### The Limitation

**Dockerfile cannot introspect base image metadata.** You cannot:

❌ Read `CMD` from base image  
❌ Read `ENTRYPOINT` from base image  
❌ Read `ENV` values from base image  
❌ Read `LABEL` values from base image  
❌ Save any base image metadata to `ARG` or `ENV`

This is a **fundamental Docker limitation** - Dockerfile directives cannot inspect image metadata.

### What You CAN Do

✅ Use `docker inspect` externally (before build)  
✅ Pass values via `--build-arg`  
✅ Convert `ARG` to `ENV` for runtime use

## Our Implementation

### The Problem

```dockerfile
FROM devpanel/php:8.3-base
# Base has CMD for apache-start.sh

ENTRYPOINT ["/usr/local/bin/deployment-entrypoint"]
# ↑ This RESETS CMD to null!

# Result: Container has no default command
```

### The Solution

We use a **3-step approach**:

#### Step 1: External Extraction (Before Build)

```bash
# extract-base-cmd.sh
BASE_CMD=$(docker inspect devpanel/php:8.3-base --format='{{json .Config.Cmd}}')
# Returns: ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh"]
```

#### Step 2: Pass as Build Argument

```bash
docker build --build-arg BASE_CMD="sudo -E /bin/bash /scripts/apache-start.sh" .
```

#### Step 3: Use in Dockerfile and Entrypoint

```dockerfile
# Dockerfile
ARG BASE_CMD="sudo -E /bin/bash /scripts/apache-start.sh"
ENV BASE_CMD="${BASE_CMD}"
ENTRYPOINT ["/usr/local/bin/deployment-entrypoint"]
```

```bash
# deployment-entrypoint.sh
if [ $# -eq 0 ]; then
  exec ${BASE_CMD}  # Use extracted CMD
else
  exec "$@"         # Use provided command
fi
```

## Why This Approach is Necessary

### Alternative Approaches (Don't Work)

❌ **Read CMD in Dockerfile**
```dockerfile
# This doesn't work - Dockerfile can't introspect
ARG BASE_CMD=$(get-base-cmd-somehow)  # ← Not possible
```

❌ **Use multi-stage build**
```dockerfile
# This doesn't work - can't read CMD from another stage
FROM base as stage1
FROM base as stage2
# Cannot copy CMD metadata between stages
```

❌ **Use shell tricks**
```dockerfile
# This doesn't work - RUN executes during build, not runtime
RUN echo "CMD=$(inspect something)" >> /etc/environment  # ← Wrong time
```

### The ONLY Solution

✅ **External script + build argument**
- Script runs before `docker build`
- Uses `docker inspect` to read base image CMD
- Passes result via `--build-arg`
- Dockerfile converts ARG to ENV
- Runtime script uses ENV variable

## Proof of Concept Tests

### Test: USER doesn't reset CMD

```bash
cat > /tmp/test-user.Dockerfile << 'EOF'
FROM devpanel/php:8.3-base
USER root
USER ${USER}
EOF

docker build -f /tmp/test-user.Dockerfile -t test-user .
docker inspect test-user --format='{{json .Config.Cmd}}'
# Output: ["sudo","-E","/bin/bash","/scripts/apache-start.sh"]
# ✓ CMD preserved!
```

### Test: ENTRYPOINT resets CMD

```bash
cat > /tmp/test-entrypoint.Dockerfile << 'EOF'
FROM devpanel/php:8.3-base
ENTRYPOINT ["/bin/bash"]
EOF

docker build -f /tmp/test-entrypoint.Dockerfile -t test-entrypoint .
docker inspect test-entrypoint --format='{{json .Config.Cmd}}'
# Output: null
# ✗ CMD was reset!
```

## Summary

| Question | Answer |
|----------|--------|
| Does USER reset CMD? | **No** - CMD is preserved |
| Does ENTRYPOINT reset CMD? | **Yes** - CMD becomes null |
| Can Dockerfile read base CMD? | **No** - Docker limitation |
| What's the solution? | External script + build arg |

## References

- [Docker Dockerfile Reference](https://docs.docker.com/engine/reference/builder/)
- [Understanding ENTRYPOINT and CMD](https://docs.docker.com/engine/reference/builder/#understand-how-cmd-and-entrypoint-interact)
- Our implementation: `extract-base-cmd.sh`, `Dockerfile`, `deployment-entrypoint.sh`
