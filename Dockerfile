# Solana Arbitrage Bot Dockerfile
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY src/ ./src/
COPY .env.example .env

# Create logs directory
RUN mkdir -p /app/logs

# Set environment variables
ENV PYTHONPATH=/app/src
ENV PYTHONUNBUFFERED=1

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash arbbot && \
    chown -R arbbot:arbbot /app
USER arbbot

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python src/mainnet_check_live.py || exit 1

# Default command
CMD ["python", "src/main.py"]

# Alternative commands:
# For live checking: CMD ["python", "src/mainnet_check_live.py", "--continuous"]
# For single check: CMD ["python", "src/mainnet_check_live.py"]

# Labels
LABEL maintainer="arbitrage-bot@example.com"
LABEL version="1.0.0"
LABEL description="Solana Flash Loan Arbitrage Bot"

# Expose port for monitoring (optional)
EXPOSE 8080

