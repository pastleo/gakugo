defmodule Gakugo.LearningFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Gakugo.Db` context.
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
      |> Gakugo.Db.create_unit()

    unit
  end

  @doc """
  Generate a page.
  """
  def page_fixture(attrs \\ %{}) do
    unit = if Map.has_key?(attrs, :unit_id), do: nil, else: unit_fixture()

    {:ok, page} =
      attrs
      |> Enum.into(%{
        items: [
          %{
            "text" => "",
            "depth" => 0,
            "flashcard" => false,
            "answer" => false,
            "textColor" => nil,
            "backgroundColor" => nil
          }
        ],
        title: "some page",
        unit_id: unit && unit.id
      })
      |> Gakugo.Db.create_page()

    page
  end
end
