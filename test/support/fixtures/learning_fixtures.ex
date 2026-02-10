defmodule Gakugo.LearningFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Gakugo.Learning` context.
  """

  @doc """
  Generate a unit.
  """
  def unit_fixture(attrs \\ %{}) do
    {:ok, unit} =
      attrs
      |> Enum.into(%{
        from_target_lang: "JA-from-zh-TW",
        title: "some title"
      })
      |> Gakugo.Learning.create_unit()

    unit
  end

  @doc """
  Generate a grammar.
  """
  def grammar_fixture(attrs \\ %{}) do
    unit = if Map.has_key?(attrs, :unit_id), do: nil, else: unit_fixture()

    {:ok, grammar} =
      attrs
      |> Enum.into(%{
        details: [
          %{"detail" => "some detail"}
        ],
        title: "some title",
        unit_id: unit && unit.id
      })
      |> Gakugo.Learning.create_grammar()

    grammar
  end

  @doc """
  Generate a vocabulary.
  """
  def vocabulary_fixture(attrs \\ %{}) do
    unit = if Map.has_key?(attrs, :unit_id), do: nil, else: unit_fixture()

    {:ok, vocabulary} =
      attrs
      |> Enum.into(%{
        from: "some from",
        note: "some note",
        target: "some target",
        unit_id: unit && unit.id
      })
      |> Gakugo.Learning.create_vocabulary()

    vocabulary
  end
end
