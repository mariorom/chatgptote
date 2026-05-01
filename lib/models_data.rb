# frozen_string_literal: true

MODELS = [
  {
    id:                  'gpt-4o',
    search_id:           'gpt-4o-search-preview',
    short_name:          'gpt-4o',
    name:                'GPT-4o',
    description:         'Most capable multimodal model — text, vision & reasoning',
    input_price:         '$2.50 / 1M tokens',
    output_price:        '$10.00 / 1M tokens',
    web_search_capable:  true,
    responses_api:       true
  },
  {
    id:                  'gpt-4o-mini',
    search_id:           'gpt-4o-mini-search-preview',
    short_name:          'gpt-4o-mini',
    name:                'GPT-4o Mini',
    description:         'Affordable, fast multimodal model for everyday tasks',
    input_price:         '$0.15 / 1M tokens',
    output_price:        '$0.60 / 1M tokens',
    web_search_capable:  true,
    responses_api:       true
  },
  {
    id:                  'chatgpt-4o-latest',
    search_id:           nil,
    short_name:          '4o-latest',
    name:                'ChatGPT-4o Latest',
    description:         'Continuously-updated GPT-4o snapshot used in ChatGPT',
    input_price:         '$5.00 / 1M tokens',
    output_price:        '$15.00 / 1M tokens',
    web_search_capable:  false,
    responses_api:       false
  },
  {
    id:                  'gpt-4-turbo',
    search_id:           nil,
    short_name:          'gpt-4-turbo',
    name:                'GPT-4 Turbo',
    description:         'High-capability GPT-4 with 128k context window',
    input_price:         '$10.00 / 1M tokens',
    output_price:        '$30.00 / 1M tokens',
    web_search_capable:  false,
    responses_api:       false
  },
  {
    id:                  'gpt-3.5-turbo',
    search_id:           nil,
    short_name:          'gpt-3.5',
    name:                'GPT-3.5 Turbo',
    description:         'Fast and cost-effective for simpler tasks',
    input_price:         '$0.50 / 1M tokens',
    output_price:        '$1.50 / 1M tokens',
    web_search_capable:  false,
    responses_api:       false
  },
  {
    id:                  'o1',
    search_id:           nil,
    short_name:          'o1',
    name:                'o1',
    description:         'Powerful reasoning model for complex problem solving',
    input_price:         '$15.00 / 1M tokens',
    output_price:        '$60.00 / 1M tokens',
    web_search_capable:  false,
    responses_api:       true
  },
  {
    id:                  'o1-mini',
    search_id:           nil,
    short_name:          'o1-mini',
    name:                'o1 Mini',
    description:         'Efficient reasoning for coding, math & STEM',
    input_price:         '$3.00 / 1M tokens',
    output_price:        '$12.00 / 1M tokens',
    web_search_capable:  false,
    responses_api:       true
  },
  {
    id:                  'o3',
    search_id:           nil,
    short_name:          'o3',
    name:                'o3',
    description:         'Most powerful reasoning model available',
    input_price:         '$10.00 / 1M tokens',
    output_price:        '$40.00 / 1M tokens',
    web_search_capable:  false,
    responses_api:       true
  },
  {
    id:                  'o3-mini',
    search_id:           nil,
    short_name:          'o3-mini',
    name:                'o3 Mini',
    description:         'Compact reasoning model — speed vs. capability balance',
    input_price:         '$1.10 / 1M tokens',
    output_price:        '$4.40 / 1M tokens',
    web_search_capable:  false,
    responses_api:       true
  }
].freeze

