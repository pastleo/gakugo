defmodule Gakugo.LearningTest do
  use Gakugo.DataCase

  alias Gakugo.Learning

  describe "units" do
    alias Gakugo.Learning.Unit

    import Gakugo.LearningFixtures

    @invalid_attrs %{title: nil, target_lang: nil, from_lang: nil}

    test "list_units/0 returns all units" do
      unit = unit_fixture()
      assert Learning.list_units() == [unit]
    end

    test "get_unit!/1 returns the unit with given id" do
      unit = unit_fixture()
      fetched_unit = Learning.get_unit!(unit.id)
      assert fetched_unit.id == unit.id
      assert fetched_unit.title == unit.title
    end

    test "create_unit/1 with valid data creates a unit" do
      valid_attrs = %{
        title: "some title",
        target_lang: "some target_lang",
        from_lang: "some from_lang"
      }

      assert {:ok, %Unit{} = unit} = Learning.create_unit(valid_attrs)
      assert unit.title == "some title"
      assert unit.target_lang == "some target_lang"
      assert unit.from_lang == "some from_lang"
    end

    test "create_unit/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Learning.create_unit(@invalid_attrs)
    end

    test "update_unit/2 with valid data updates the unit" do
      unit = unit_fixture()

      update_attrs = %{
        title: "some updated title",
        target_lang: "some updated target_lang",
        from_lang: "some updated from_lang"
      }

      assert {:ok, %Unit{} = unit} = Learning.update_unit(unit, update_attrs)
      assert unit.title == "some updated title"
      assert unit.target_lang == "some updated target_lang"
      assert unit.from_lang == "some updated from_lang"
    end

    test "update_unit/2 with invalid data returns error changeset" do
      unit = unit_fixture()
      assert {:error, %Ecto.Changeset{}} = Learning.update_unit(unit, @invalid_attrs)
      fetched_unit = Learning.get_unit!(unit.id)
      assert fetched_unit.id == unit.id
    end

    test "delete_unit/1 deletes the unit" do
      unit = unit_fixture()
      assert {:ok, %Unit{}} = Learning.delete_unit(unit)
      assert_raise Ecto.NoResultsError, fn -> Learning.get_unit!(unit.id) end
    end

    test "change_unit/1 returns a unit changeset" do
      unit = unit_fixture()
      assert %Ecto.Changeset{} = Learning.change_unit(unit)
    end
  end

  describe "grammars" do
    alias Gakugo.Learning.Grammar

    import Gakugo.LearningFixtures

    @invalid_attrs %{title: nil, details: nil}

    test "list_grammars/0 returns all grammars" do
      grammar = grammar_fixture()
      assert Learning.list_grammars() == [grammar]
    end

    test "get_grammar!/1 returns the grammar with given id" do
      grammar = grammar_fixture()
      assert Learning.get_grammar!(grammar.id) == grammar
    end

    test "create_grammar/1 with valid data creates a grammar" do
      unit = unit_fixture()

      valid_attrs = %{
        title: "some title",
        details: [
          %{"detail" => "some detail"}
        ],
        unit_id: unit.id
      }

      assert {:ok, %Grammar{} = grammar} = Learning.create_grammar(valid_attrs)
      assert grammar.title == "some title"
      assert grammar.details == valid_attrs.details
    end

    test "create_grammar/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Learning.create_grammar(@invalid_attrs)
    end

    test "update_grammar/2 with valid data updates the grammar" do
      grammar = grammar_fixture()

      update_attrs = %{
        title: "some updated title",
        details: [
          %{"detail" => "some updated detail"}
        ]
      }

      assert {:ok, %Grammar{} = grammar} = Learning.update_grammar(grammar, update_attrs)
      assert grammar.title == "some updated title"
      assert grammar.details == update_attrs.details
    end

    test "update_grammar/2 with invalid data returns error changeset" do
      grammar = grammar_fixture()
      assert {:error, %Ecto.Changeset{}} = Learning.update_grammar(grammar, @invalid_attrs)
      assert grammar == Learning.get_grammar!(grammar.id)
    end

    test "delete_grammar/1 deletes the grammar" do
      grammar = grammar_fixture()
      assert {:ok, %Grammar{}} = Learning.delete_grammar(grammar)
      assert_raise Ecto.NoResultsError, fn -> Learning.get_grammar!(grammar.id) end
    end

    test "change_grammar/1 returns a grammar changeset" do
      grammar = grammar_fixture()
      assert %Ecto.Changeset{} = Learning.change_grammar(grammar)
    end
  end

  describe "vocabularies" do
    alias Gakugo.Learning.Vocabulary

    import Gakugo.LearningFixtures

    @invalid_attrs %{target: nil, from: nil, note: nil}

    test "list_vocabularies/0 returns all vocabularies" do
      vocabulary = vocabulary_fixture()
      assert Learning.list_vocabularies() == [vocabulary]
    end

    test "get_vocabulary!/1 returns the vocabulary with given id" do
      vocabulary = vocabulary_fixture()
      assert Learning.get_vocabulary!(vocabulary.id) == vocabulary
    end

    test "create_vocabulary/1 with valid data creates a vocabulary" do
      unit = unit_fixture()

      valid_attrs = %{
        target: "some target",
        from: "some from",
        note: "some note",
        unit_id: unit.id
      }

      assert {:ok, %Vocabulary{} = vocabulary} = Learning.create_vocabulary(valid_attrs)
      assert vocabulary.target == "some target"
      assert vocabulary.from == "some from"
      assert vocabulary.note == "some note"
    end

    test "create_vocabulary/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Learning.create_vocabulary(@invalid_attrs)
    end

    test "update_vocabulary/2 with valid data updates the vocabulary" do
      vocabulary = vocabulary_fixture()

      update_attrs = %{
        target: "some updated target",
        from: "some updated from",
        note: "some updated note"
      }

      assert {:ok, %Vocabulary{} = vocabulary} =
               Learning.update_vocabulary(vocabulary, update_attrs)

      assert vocabulary.target == "some updated target"
      assert vocabulary.from == "some updated from"
      assert vocabulary.note == "some updated note"
    end

    test "update_vocabulary/2 with invalid data returns error changeset" do
      vocabulary = vocabulary_fixture()
      assert {:error, %Ecto.Changeset{}} = Learning.update_vocabulary(vocabulary, @invalid_attrs)
      assert vocabulary == Learning.get_vocabulary!(vocabulary.id)
    end

    test "delete_vocabulary/1 deletes the vocabulary" do
      vocabulary = vocabulary_fixture()
      assert {:ok, %Vocabulary{}} = Learning.delete_vocabulary(vocabulary)
      assert_raise Ecto.NoResultsError, fn -> Learning.get_vocabulary!(vocabulary.id) end
    end

    test "change_vocabulary/1 returns a vocabulary changeset" do
      vocabulary = vocabulary_fixture()
      assert %Ecto.Changeset{} = Learning.change_vocabulary(vocabulary)
    end
  end
end
