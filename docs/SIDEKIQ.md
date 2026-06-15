# Sidekiq Job Processing

This application uses Sidekiq for background processing of PDF ingestion jobs.

## Setup

1. **Install Redis** (if not already installed):

   ```bash
   # macOS
   brew install redis
   brew services start redis

   # Ubuntu/Debian
   sudo apt-get install redis-server
   sudo systemctl start redis
   ```

2. **Start Sidekiq worker**:

   ```bash
   bin/sidekiq
   ```

3. **Access Sidekiq Web UI** (development only):
   - Visit: http://localhost:3000/sidekiq
   - Monitor job queues, failures, and statistics

## Usage

### Automatic Processing

When you upload a PDF file through the web interface, it will:

1. Create an `Upload` record
2. Create an `IngestionJob` with status "queued"
3. Enqueue a `ProcessIngestionJob` for background processing
4. Return immediately with a "queued" status

### Manual Processing

You can also process jobs manually using rake tasks:

```bash
# Process the next queued job
bin/rails ingestion:process_next

# Process all queued jobs
bin/rails ingestion:process_all

# Check job status
bin/rails ingestion:status
```

### Job States

- **queued**: Job is waiting to be processed
- **processing**: Job is currently being processed
- **completed**: Job finished successfully
- **failed**: Job failed with an error

### Monitoring

- Check the Sidekiq web interface for real-time monitoring
- Use `bin/rails ingestion:status` for a quick status overview
- Failed jobs will be retried up to 3 times automatically

## Configuration

Sidekiq is configured to use Redis at `redis://localhost:6379/0` by default.
You can override this with the `REDIS_URL` environment variable.

## Troubleshooting

1. **Redis not running**: Start Redis service
2. **Sidekiq not processing**: Check if Sidekiq worker is running
3. **Jobs failing**: Check logs and Sidekiq web interface for error details
4. **Memory issues**: Adjust Sidekiq concurrency in `config/initializers/sidekiq.rb`
