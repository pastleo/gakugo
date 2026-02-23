defmodule Gakugo.AI.ConfigTest do
  use ExUnit.Case, async: true

  alias Gakugo.AI.Config

  setup do
    previous = Application.get_env(:gakugo, :ai)

    Application.put_env(:gakugo, :ai,
      providers: [
        ollama: [base_url: "http://localhost:11434", api_key: nil, host_header: "localhost"],
        openai: [base_url: "https://api.openai.com/v1", api_key: "sk-test-openai-1234"],
        gemini: [base_url: "https://generativelanguage.googleapis.com/v1beta", api_key: "abcd"]
      ],
      defaults: [
        parse: [provider: :openai, model: "gpt-4o-mini"],
        generation: [provider: :openai, model: "gpt-4o-mini"],
        ocr: [provider: :gemini, model: "gemini-2.0-flash"]
      ]
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:gakugo, :ai, previous)
      else
        Application.delete_env(:gakugo, :ai)
      end
    end)

    :ok
  end

  test "returns provider and usage selections" do
    assert Config.usage_provider(:parse) == :openai
    assert Config.usage_model(:parse) == "gpt-4o-mini"
    assert Config.usage_provider(:generation) == :openai
    assert Config.usage_model(:generation) == "gpt-4o-mini"
    assert Config.usage_provider(:ocr) == :gemini
    assert Config.usage_model(:ocr) == "gemini-2.0-flash"
  end

  test "effective view masks and summarizes api keys" do
    effective = Config.effective()

    assert effective.providers.openai.api_key_present?
    assert effective.providers.openai.api_key_preview == "sk-t...1234"

    assert effective.providers.gemini.api_key_present?
    assert effective.providers.gemini.api_key_preview == "***"

    refute effective.providers.ollama.api_key_present?
    assert effective.providers.ollama.api_key_preview == nil
  end
end
