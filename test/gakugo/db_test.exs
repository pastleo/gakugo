defmodule Gakugo.DbTest do
  use Gakugo.DataCase

  alias Gakugo.Db

  describe "units" do
    alias Gakugo.Db.Unit

    import Gakugo.LearningFixtures

    @invalid_attrs %{title: nil, from_target_lang: nil}

    test "list_units/0 returns all units" do
      unit = unit_fixture()
      assert Db.list_units() == [unit]
    end

    test "get_unit!/1 returns the unit with given id" do
      unit = unit_fixture()
      fetched_unit = Db.get_unit!(unit.id)
      assert fetched_unit.id == unit.id
      assert fetched_unit.title == unit.title
    end

    test "create_unit/1 with valid data creates a unit and default page" do
      valid_attrs = %{title: "some title", from_target_lang: "JA-from-zh-TW"}

      assert {:ok, %Unit{} = unit} = Db.create_unit(valid_attrs)
      unit = Db.get_unit!(unit.id)
      assert unit.title == "some title"
      assert unit.from_target_lang == "JA-from-zh-TW"
      assert length(unit.pages) == 1
      assert hd(unit.pages).title == "Page 1"
    end

    test "create_unit/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Db.create_unit(@invalid_attrs)
    end

    test "create_unit/1 with invalid from_target_lang returns error changeset" do
      invalid_attrs = %{title: "some title", from_target_lang: "invalid-lang"}
      assert {:error, %Ecto.Changeset{}} = Db.create_unit(invalid_attrs)
    end

    test "update_unit/2 with valid data updates the unit" do
      unit = unit_fixture()

      update_attrs = %{
        title: "some updated title",
        from_target_lang: "JA-from-zh-TW"
      }

      assert {:ok, %Unit{} = unit} = Db.update_unit(unit, update_attrs)
      assert unit.title == "some updated title"
      assert unit.from_target_lang == "JA-from-zh-TW"
    end

    test "update_unit/2 with invalid data returns error changeset" do
      unit = unit_fixture()
      assert {:error, %Ecto.Changeset{}} = Db.update_unit(unit, @invalid_attrs)
      fetched_unit = Db.get_unit!(unit.id)
      assert fetched_unit.id == unit.id
    end

    test "delete_unit/1 soft deletes the unit" do
      unit = unit_fixture()

      assert {:ok, %Unit{}} = Db.delete_unit(unit)
      assert_raise Ecto.NoResultsError, fn -> Db.get_unit!(unit.id) end

      deleted_unit = Db.get_unit_with_deleted!(unit.id)
      assert deleted_unit.deleted_at
      assert Db.list_units() == []
      assert Enum.map(Db.list_deleted_units(), & &1.id) == [unit.id]
    end

    test "restore_unit/1 restores a soft deleted unit" do
      unit = unit_fixture()
      assert {:ok, %Unit{}} = Db.delete_unit(unit)

      deleted_unit = Db.get_unit_with_deleted!(unit.id)
      assert {:ok, %Unit{} = restored_unit} = Db.restore_unit(deleted_unit)

      assert is_nil(restored_unit.deleted_at)
      assert Db.get_unit!(unit.id).id == unit.id
      assert Db.list_deleted_units() == []
    end

    test "change_unit/1 returns a unit changeset" do
      unit = unit_fixture()
      assert %Ecto.Changeset{} = Db.change_unit(unit)
    end
  end

  describe "pages" do
    alias Gakugo.Db.Page

    import Gakugo.LearningFixtures

    @invalid_attrs %{title: nil, unit_id: nil}

    test "list_pages_for_unit/1 returns all pages for a unit" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = page_fixture(%{unit_id: unit.id})

      assert Enum.map(Db.list_pages_for_unit(unit.id), & &1.id) == [
               hd(unit.pages).id,
               page.id
             ]
    end

    test "create_page/1 with valid data creates a page" do
      unit = unit_fixture()

      valid_attrs = %{
        title: "Page X",
        unit_id: unit.id,
        items: [%{"text" => "hello", "flashcard" => true, "children" => []}]
      }

      assert {:ok, %Page{} = page} = Db.create_page(valid_attrs)
      assert page.title == "Page X"
      assert page.items == valid_attrs.items
      assert page.position == 2
    end

    test "create_page/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Db.create_page(@invalid_attrs)
    end

    test "update_page/2 with valid data updates the page" do
      page = page_fixture()

      update_attrs = %{
        title: "Updated Page",
        items: [%{"text" => "updated", "depth" => 0, "flashcard" => false, "answer" => false}]
      }

      assert {:ok, %Page{} = page} = Db.update_page(page, update_attrs)
      assert page.title == "Updated Page"
      assert page.items == update_attrs.items
    end

    test "update_page/2 with invalid data returns error changeset" do
      page = page_fixture()
      assert {:error, %Ecto.Changeset{}} = Db.update_page(page, @invalid_attrs)
      assert page.id == Db.get_page!(page.id).id
    end

    test "delete_page/1 deletes the page" do
      page = page_fixture()
      assert {:ok, %Page{}} = Db.delete_page(page)
      assert_raise Ecto.NoResultsError, fn -> Db.get_page!(page.id) end
    end

    test "change_page/1 returns a page changeset" do
      page = page_fixture()
      assert %Ecto.Changeset{} = Db.change_page(page)
    end

    test "move_page/2 swaps page ordering within unit" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      first_page = hd(unit.pages)

      {:ok, second_page} =
        Db.create_page(%{
          title: "Page 2",
          unit_id: unit.id,
          items: [%{"text" => "", "flashcard" => false, "children" => []}]
        })

      {:ok, third_page} =
        Db.create_page(%{
          title: "Page 3",
          unit_id: unit.id,
          items: [%{"text" => "", "depth" => 0, "flashcard" => false, "answer" => false}]
        })

      assert Enum.map(Db.list_pages_for_unit(unit.id), & &1.id) == [
               first_page.id,
               second_page.id,
               third_page.id
             ]

      assert Enum.map(Db.list_pages_for_unit(unit.id), & &1.position) == [1, 2, 3]

      assert {:ok, :moved} = Db.move_page(second_page, :up)

      assert Enum.map(Db.list_pages_for_unit(unit.id), & &1.id) == [
               second_page.id,
               first_page.id,
               third_page.id
             ]

      assert Enum.map(Db.list_pages_for_unit(unit.id), & &1.position) == [1, 2, 3]

      assert {:ok, :moved} = Db.move_page(second_page, :down)

      assert Enum.map(Db.list_pages_for_unit(unit.id), & &1.id) == [
               first_page.id,
               second_page.id,
               third_page.id
             ]

      assert Enum.map(Db.list_pages_for_unit(unit.id), & &1.position) == [1, 2, 3]
    end

    test "move_page/2 returns boundary error at list edge" do
      unit = unit_fixture()
      first_page = unit.id |> Db.get_unit!() |> Map.get(:pages) |> hd()

      assert {:error, :boundary} = Db.move_page(first_page, :up)
    end
  end
end
