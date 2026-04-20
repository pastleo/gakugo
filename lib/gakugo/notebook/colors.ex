defmodule Gakugo.Notebook.Colors do
  @moduledoc """
  Shared notebook color palette for item-level and future inline color systems.
  The source of truth lives in `priv/notebook_colors.json`.
  """

  @palette_path Path.expand("../../../priv/notebook_colors.json", __DIR__)
  @external_resource @palette_path
  @palette Jason.decode!(File.read!(@palette_path))
  @color_names Enum.map(@palette, & &1["name"])
  @colors_by_name Map.new(@palette, &{&1["name"], &1})

  def names, do: @color_names

  def valid_name?(value) when is_binary(value), do: value in @color_names
  def valid_name?(_), do: false

  def definition(name) when is_binary(name) do
    Map.get(@colors_by_name, name)
  end

  def definition(_), do: nil

  def hex(name, role, theme) when is_binary(name) and role in [:foreground, :background] do
    hex(name, Atom.to_string(role), theme)
  end

  def hex(name, role, theme)
      when is_binary(name) and role in ["foreground", "background"] and theme in [:light, :dark] do
    hex(name, role, Atom.to_string(theme))
  end

  def hex(name, role, theme)
      when is_binary(name) and role in ["foreground", "background"] and theme in ["light", "dark"] do
    with %{} = color <- definition(name),
         %{} = theme_map <- Map.get(color, theme),
         value when is_binary(value) <- Map.get(theme_map, role) do
      value
    else
      _ -> nil
    end
  end

  def hex(_name, _role, _theme), do: nil
end
