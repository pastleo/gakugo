# This file contains local development overrides.
# Copy this to dev.local.exs and modify as needed.
# dev.local.exs is gitignored and will not be committed.

import Config

# AI provider configuration
# Uncomment and modify to override provider endpoints/keys and defaults.
# config :gakugo, :ai,
#   providers: [
#     gemini: [
#       api_key: "..."
#     ],
#     openai: [
#       api_key: "sk-..."
#     ],
#     ollama: [
#       base_url: "http://localhost:11434",
#     ]
#   ],
#   defaults: [
#     ocr: [provider: :gemini, model: "gemini-2.5-flash"],
#     parse: [provider: :gemini, model: "gemini-2.5-flash"],
#     generation: [provider: :gemini, model: "gemini-2.5-flash"]
#   ]

# use other than 4000 port
# config :gakugo, GakugoWeb.Endpoint, http: [port: xxxx]
