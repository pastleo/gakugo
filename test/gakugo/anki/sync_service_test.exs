defmodule Gakugo.Anki.SyncServiceTest do
  use Gakugo.DataCase, async: true

  alias Gakugo.Anki.SyncService
  alias Gakugo.Learning

  import Gakugo.LearningFixtures

  describe "preview_unit_flashcards/1" do
    test "builds one card per front node, including fronts without answer descendants" do
      unit = unit_fixture()
      unit = Learning.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Learning.update_page(page, %{
          items: [
            %{"text" => "front without answer", "front" => true, "children" => []},
            %{
              "text" => "front with answer",
              "front" => true,
              "children" => [
                %{"text" => "revealed answer", "answer" => true, "children" => []}
              ]
            }
          ]
        })

      _second_page =
        page_fixture(%{
          unit_id: unit.id,
          title: "Page 2",
          items: [
            %{"text" => "another front", "front" => true, "children" => []}
          ]
        })

      cards =
        unit.id
        |> Learning.get_unit!()
        |> SyncService.preview_unit_flashcards()

      assert length(cards) == 3
      assert Enum.all?(cards, fn card -> Map.keys(card) |> Enum.sort() == [:content, :id] end)

      assert Enum.any?(cards, fn card ->
               String.contains?(card.content, "front without answer")
             end)

      assert Enum.any?(cards, fn card -> String.contains?(card.content, "another front") end)

      assert Enum.any?(cards, fn card ->
               String.contains?(card.content, "revealed answer")
             end)
    end

    test "highlights all nodes under the current flashcard tree" do
      unit = unit_fixture()
      unit = Learning.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Learning.update_page(page, %{
          items: [
            %{
              "text" => "front root",
              "front" => true,
              "children" => [
                %{"text" => "child one", "children" => []},
                %{"text" => "child two", "children" => []}
              ]
            },
            %{"text" => "outside node", "children" => []}
          ]
        })

      [card] =
        unit.id
        |> Learning.get_unit!()
        |> SyncService.preview_unit_flashcards()

      assert String.contains?(card.content, "front root")
      assert String.contains?(card.content, "child one")
      assert String.contains?(card.content, "child two")
      assert String.contains?(card.content, "outside node")

      assert String.contains?(card.content, ~s(class="gakugo-front gakugo-front-tree"))
      assert String.contains?(card.content, ~s(class="gakugo-front-tree">child one))
      assert String.contains?(card.content, ~s(class="gakugo-front-tree">child two))
      assert String.contains?(card.content, ~s(class="">outside node))
    end
  end
end
