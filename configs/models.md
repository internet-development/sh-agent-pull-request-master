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
