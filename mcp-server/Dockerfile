# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install all dependencies (including devDependencies for build)
RUN npm ci

# Cache bust arg - changes with each commit to invalidate source cache
ARG CACHE_BUST=unknown

# Copy source code and UI
COPY tsconfig.json vite.config.ts ./
COPY src/ ./src/
COPY ui/ ./ui/

# Build TypeScript + UI + copy patterns
RUN npm run build

# Production stage
FROM node:20-alpine

WORKDIR /app

# Copy package files and install production dependencies only
COPY package*.json ./
RUN npm ci --omit=dev

# Copy built files from builder
COPY --from=builder /app/dist ./dist

# Set environment variables
ENV NODE_ENV=production
ENV MCP_TRANSPORT=http
ENV PORT=3001

# Expose port
EXPOSE 3001

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3001/health || exit 1

# Run the server
CMD ["node", "dist/server.js"]
