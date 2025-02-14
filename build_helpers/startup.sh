#!/bin/bash
set -e

# Create necessary directories
echo "Creating required directories..."
mkdir -p /freqtrade/user_data/data
mkdir -p /freqtrade/user_data/logs
mkdir -p /freqtrade/user_data/models
mkdir -p /freqtrade/user_data/strategies
mkdir -p /freqtrade/user_data/notebooks
mkdir -p /freqtrade/user_data/plots

# Sync data with retry logic
echo "Syncing data from GCP bucket..."
MAX_RETRIES=3
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if gsutil -m rsync -r -d gs://milka_user_data/user_data /freqtrade/user_data/; then
        echo "Sync completed successfully"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "Sync failed, retrying in 5 seconds... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
            sleep 5
        else
            echo "Failed to sync after $MAX_RETRIES attempts"
            exit 1
        fi
    fi
done

echo "Starting FreqTrade..."
# Start FreqTrade application
exec freqtrade trade \
    --logfile /freqtrade/user_data/logs/freqtrade.log \
    --db-url sqlite:////freqtrade/user_data/tradesv3.sqlite \
    --config /freqtrade/user_data/config.json \
    --strategy MomentumStrategy \
    --freqaimodel BTCPredictionModel
