# Workflow: Research Solution

This workflow is executed by the **Researcher** persona when external information is needed.

## Overview

The Researcher has two responsibilities:
1. **Web Research Phase**: Search the web for current factual information using Google Custom Search API
2. **Code Review Phase**: Review code for best practices, security, and performance

## When Research Happens

Research is triggered by the Director during planning. The Director identifies topics that need current information:

- Package versions (npm, pip, cargo, etc.)
- API documentation and changes
- Framework best practices
- Security advisories
- Breaking changes in dependencies

## Research Flow

```
Director creates plan
       │
       ▼
┌──────────────────────────────┐
│ research_queries: [          │
│   "Latest stable Next.js?",  │
│   "React 19 Server API docs" │
│ ]                            │
└──────────────────────────────┘
       │
       ▼
┌──────────────────────────────┐
│ Google Custom Search API     │
│ (for each query)             │
└──────────────────────────────┘
       │
       ▼
┌──────────────────────────────┐
│ Researcher synthesizes       │
│ findings into actionable     │
│ information                  │
└──────────────────────────────┘
       │
       ▼
Findings shared with all personas
```

## Google Custom Search API

The agent uses Google's Custom Search API for web research:

```bash
curl "https://www.googleapis.com/customsearch/v1?key=${API_KEY_GOOGLE_CUSTOM_SEARCH}&cx=${GOOGLE_CUSTOM_SEARCH_ID}&q=latest+nextjs+version&num=5"
```

### Setup Requirements

1. **API Key**: Get from https://console.cloud.google.com/apis/credentials
2. **Custom Search Engine ID**: Create at https://programmablesearchengine.google.com/
   - Set to search the entire web
   - Copy the Search Engine ID (cx parameter)

### Environment Variables

```bash
API_KEY_GOOGLE_CUSTOM_SEARCH=your_api_key
GOOGLE_CUSTOM_SEARCH_ID=your_search_engine_id
```

### Response Structure

```json
{
  "items": [
    {
      "title": "Page Title",
      "link": "https://example.com/page",
      "snippet": "Relevant excerpt from the page..."
    }
  ],
  "searchInformation": {
    "totalResults": "1234567"
  }
}
```

## Research Output Format

The Researcher synthesizes search results into:

```json
{
  "research_conducted": true,
  "queries_searched": ["query1", "query2"],
  "findings": [
    {
      "query": "the original search query",
      "answer": "clear, direct answer",
      "confidence": "high|medium|low",
      "key_facts": ["specific fact 1", "specific fact 2"],
      "sources": [{"url": "...", "title": "..."}]
    }
  ],
  "summary": "Overall synthesis relevant to the task",
  "warnings": ["critical warnings, deprecations, security concerns"]
}
```

## Confidence Levels

- **High**: Official documentation, release notes, authoritative sources (GitHub, npm)
- **Medium**: Reputable tech blogs, well-known community resources
- **Low**: Dated sources, community forums, conflicting information

## How Findings Are Used

Research findings are passed to:

1. **All Personas** during consultation - they can reference verified facts
2. **Requirements Synthesis** - findings become constraints and requirements
3. **Engineer** during implementation - has access to verified versions/APIs
4. **Review Phase** - reviewers check if research findings were applied correctly

## Fallback Behavior

If research fails (API unavailable, keys not configured, no results):
- Log a warning
- Continue with existing knowledge
- All personas proceed with caution on external dependencies

## Quality Gates

- [ ] Each finding cites specific sources
- [ ] Confidence levels are assigned
- [ ] Warnings are highlighted
- [ ] Version numbers are exact, not approximate
- [ ] Conflicting information is noted

## When NOT to Research

The Director should NOT request research when:
- Task is purely internal refactoring
- No external dependencies involved
- Codebase already documents required patterns
- Changes don't affect package versions or APIs
