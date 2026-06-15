# Ollama Configuration
# 
# To use the multi-stage PDF pipeline with Ollama:
# 
# 1. Set OLLAMA_URL environment variable:
#    OLLAMA_URL=http://8.213.84.103:11434
# 
# 2. Optionally set OLLAMA_MODEL (defaults to "qwen-wte"):
#    OLLAMA_MODEL=qwen-wte
# 
# 3. Ensure the Ollama server is accessible and the model is created:
#    ssh -i Alex-LLM.pem root@8.213.84.103
#    ollama create qwen-wte -f Modelfile-wte
# 
# If OLLAMA_URL is not set, the system will fallback to OpenRouter.
#
# --- Ollama proxy (when Ollama is behind a firewall) ---
# Deploy the app on the server where Ollama runs. The proxy is at POST/GET /ollama_proxy/*.
#
# On the server (where Ollama runs):
#   OLLAMA_URL=http://localhost:11434
#   OLLAMA_PROXY_SECRET=<secure-random-token>   # e.g. rails runner "puts SecureRandom.hex(32)"
#
# Locally (to use the proxy):
#   OLLAMA_PROXY_URL=https://your-app.com/ollama_proxy
#   OLLAMA_PROXY_TOKEN=<same value as OLLAMA_PROXY_SECRET>
#
# Send token in header: Authorization: Bearer <token> or X-Ollama-Proxy-Token: <token>.

