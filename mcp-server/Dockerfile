FROM python:3.12-slim

WORKDIR /app

COPY mcp-server/pyproject.toml pyproject.toml
COPY mcp-server/src/ src/
RUN pip install --no-cache-dir .

COPY config/patterns/ config/patterns/

RUN adduser --disabled-password --no-create-home appuser
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import socket; s=socket.create_connection(('localhost',8000),timeout=5); s.close()"

ENV MCP_HOST=0.0.0.0
CMD ["python", "-m", "src.server"]
