defmodule Gakugo.Learning.Grammar do
  use Ecto.Schema
  import Ecto.Changeset

  schema "grammars" do
    field :title, :string
    field :details, {:array, :map}
    field :details_json, :string, virtual: true
    belongs_to :unit, Gakugo.Learning.Unit

    timestamps(type: :utc_datetime)
  end

  def changeset(grammar, attrs) do
    grammar
    |> cast(attrs, [:title, :details, :details_json, :unit_id])
    |> validate_required([:title, :unit_id])
    |> validate_details()
  end

  defp validate_details(changeset) do
    case get_change(changeset, :details) do
      nil ->
        changeset

      details when is_list(details) ->
        if Enum.all?(details, &valid_detail_item?/1) do
          changeset
        else
          add_error(changeset, :details, "invalid structure")
        end

      _ ->
        add_error(changeset, :details, "must be a list")
    end
  end

  defp valid_detail_item?(%{"detail" => detail} = item) when is_binary(detail) do
    case Map.get(item, "children") do
      nil -> true
      children when is_list(children) -> Enum.all?(children, &valid_detail_item?/1)
      _ -> false
    end
  end

  defp valid_detail_item?(_), do: false
end
