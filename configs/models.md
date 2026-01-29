# Model Configuration

```json
{
  "models": {
    "programming": {
      "provider": "anthropic",
      "model": "claude-opus-4-5",
      "env_key": "API_KEY_ANTHROPIC"
    },
    "reasoning": {
      "provider": "openai", 
      "model": "gpt-5.2-chat-latest",
      "env_key": "API_KEY_OPEN_AI"
    },
    "human-simulated": {
      "provider": "openai",
      "model": "gpt-5.2-chat-latest",
      "env_key": "API_KEY_OPEN_AI"
    },
    "research": {
      "provider": "openai",
      "model": "gpt-5.2-chat-latest",
      "env_key": "API_KEY_OPEN_AI"
    }
  },
  "persona_model_mapping": {
    "Director": "reasoning",
    "Engineer": "programming",
    "Researcher": "research",
    "Project Manager": "reasoning",
    "Technical Writer": "human-simulated"
  },
  "web_search": {
    "provider": "google",
    "env_keys": ["API_KEY_GOOGLE_CUSTOM_SEARCH", "GOOGLE_CUSTOM_SEARCH_ID"]
  }
}
```

---

## Model Compatibility Notes (2025–2026)

### Provider Stability

| Provider | Status | Notes |
|----------|--------|-------|
| Anthropic | Stable | Claude models are well-supported. Check for region-based routing if experiencing latency. |
| OpenAI | Stable | Models are versioned; older versions may be deprecated with limited notice. |
| Google | Requires Setup | May require quota project ID configuration for higher rate limits. |

### Recommendations

- **Pin model versions** in your configuration when possible (e.g., `claude-3-opus-20240229` rather than `claude-3-opus`)
- **Monitor deprecation notices** from providers—model availability can change
- **Test API connectivity** with `./agent.sh test-models` before long runs
- **Have fallback keys** if using multiple providers

### Known Limitations

- Model responses are non-deterministic; the same prompt may produce different outputs
- Rate limits vary by provider and subscription tier
- Some models have context length limits that may truncate large file contents
