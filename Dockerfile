# Build openclaw from source to avoid npm packaging gaps (some dist files are not shipped).
FROM node:22-bookworm AS openclaw-build

# Dependencies needed for openclaw build
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (openclaw build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /openclaw

# Pin to a known ref (tag/branch). If it doesn't exist, fall back to main.
ARG OPENCLAW_GIT_REF=main
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch: relax version requirements for packages that may reference unpublished versions.
# Apply to all extension package.json files to handle workspace protocol (workspace:*).
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

RUN pnpm install --no-frozen-lockfile
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build


# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    build-essential \
    gcc \
    g++ \
    make \
    procps \
    file \
    git \
    python3 \
    python3-pip \
    pkg-config \
    sudo \
    jq \
    ripgrep \
    ffmpeg \
  && rm -rf /var/lib/apt/lists/*

# Install Homebrew (must run as non-root user)
# Create a user for Homebrew installation, install it, then make it accessible to all users
RUN useradd -m -s /bin/bash linuxbrew \
  && echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER linuxbrew
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

# ── OpenClaw Skills: Homebrew CLI tools (must run as linuxbrew, not root) ──
RUN brew install gh himalaya yt-dlp

USER root

# ── OpenClaw Skills: npm CLI tools ──
# summarize brew formula is macOS-only (ARM64 binary), so install via npm instead
RUN npm install -g @steipete/summarize @steipete/bird clawhub mcporter twitter-api-v2 @blockrun/clawrouter viem "@solana/web3.js@^1" @polymarket/clob-client ethers@5

WORKDIR /app

# Wrapper deps
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod --frozen-lockfile && pnpm store prune

# Copy built openclaw
COPY --from=openclaw-build /openclaw /openclaw

# Provide a openclaw executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src

# Install custom skill CLIs
RUN chmod +x /app/src/skills/x-api/x-api.mjs \
  && ln -sf /app/src/skills/x-api/x-api.mjs /usr/local/bin/x-api \
  && chmod +x /app/src/skills/moon/moon.mjs \
  && ln -sf /app/src/skills/moon/moon.mjs /usr/local/bin/moon

# Debug: show where OpenClaw stores built-in skills and model registry (visible in Railway build logs)
RUN echo "=== OpenClaw SKILL.md locations ===" \
  && find /openclaw -name "SKILL.md" -type f 2>/dev/null; \
  echo "=== /openclaw top-level ===" && ls /openclaw/ 2>/dev/null; \
  echo "=== OpenClaw model registry files (kimi-k2 references) ===" \
  && grep -rl "kimi-k2" /openclaw/dist/ 2>/dev/null | head -10; \
  echo "=== OpenClaw model registry files (openrouter references) ===" \
  && grep -rl "openrouter" /openclaw/dist/ 2>/dev/null | head -10; true

# Copy custom skills into OpenClaw's source tree so the gateway discovers them.
# Auto-detect the skills root by finding a built-in SKILL.md and going two levels up.
RUN SKILL_MD=$(find /openclaw -name "SKILL.md" -type f 2>/dev/null | head -1) && \
  if [ -n "$SKILL_MD" ]; then \
    SKILLS_ROOT=$(dirname "$(dirname "$SKILL_MD")") && \
    echo "[skills] Auto-detected skills root: $SKILLS_ROOT" && \
    cp -r /app/src/skills/* "$SKILLS_ROOT/" && \
    echo "[skills] Installed custom skills:" && ls "$SKILLS_ROOT/"; \
  else \
    echo "[skills] No built-in SKILL.md found in /openclaw" && \
    echo "[skills] Trying fallback: /openclaw/skills/" && \
    mkdir -p /openclaw/skills && \
    cp -r /app/src/skills/* /openclaw/skills/ && \
    echo "[skills] Installed to /openclaw/skills/:" && ls /openclaw/skills/; \
  fi

ENV PORT=8080
EXPOSE 8080

# Clean ClawRouter plugin artifacts from persistent volume and home dir.
# ONLY search /data and /root — do NOT search /openclaw (would break @buape/carbon/dist/src/plugins).
# Copy custom skills to multiple discovery paths + clean stale bags dirs.
# Then start the server which eagerly boots the gateway via direct JSON token sync (no CLI).
CMD ["sh", "-c", "\
if [ \"$USE_CLAWROUTER\" = \"true\" ]; then \
  echo '[boot] ClawRouter enabled, skipping plugin cleanup'; \
else \
  echo '[boot] Cleaning ClawRouter artifacts...' && \
  find /data /root -type d -name plugins 2>/dev/null | while read d; do echo \"[boot] rm dir: $d\"; rm -rf \"$d\"; done && \
  find /data /root -maxdepth 6 \\( -iname '*clawrouter*' -o -iname '*blockrun*' \\) 2>/dev/null | while read f; do echo \"[boot] rm artifact: $f\"; rm -rf \"$f\"; done && \
  echo '[boot] Cleanup done'; \
fi && \
echo '[boot] Cleaning stale bags skill from persistent volume...' && \
rm -rf /data/.openclaw/skills/bags /data/workspace/skills/bags /root/.openclaw/skills/bags 2>/dev/null; \
echo '[boot] Installing custom skills to all discovery paths...' && \
mkdir -p /data/.openclaw/skills /data/workspace/skills /root/.openclaw/skills && \
cp -r /app/src/skills/* /data/.openclaw/skills/ 2>/dev/null && \
cp -r /app/src/skills/* /data/workspace/skills/ 2>/dev/null && \
cp -r /app/src/skills/* /root/.openclaw/skills/ 2>/dev/null && \
echo '[boot] Custom skills installed' && \
echo '[boot] Built-in SKILL.md files:' && find /openclaw -name 'SKILL.md' -type f 2>/dev/null | head -10 && \
echo '[boot] Custom skills in workspace:' && ls /data/workspace/skills/ 2>/dev/null && \
echo '[boot] Custom skills in home:' && ls /root/.openclaw/skills/ 2>/dev/null && \
node src/server.js"]
