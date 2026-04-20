defmodule Gakugo.Notebook.Item.YStateAsUpdate do
  @moduledoc false

  alias MDEx
  alias Yex.Doc
  alias Yex.XmlElementPrelim
  alias Yex.XmlFragment
  alias Yex.XmlTextPrelim

  @fragment_name "prosemirror"

  def hydrate_item(%{} = item) do
    if Map.get(item, "yStateAsUpdate", Map.get(item, :yStateAsUpdate)) do
      item
    else
      case hydrate_text(Map.get(item, "text", Map.get(item, :text))) do
        nil -> item
        y_state_as_update -> Map.put(item, "yStateAsUpdate", y_state_as_update)
      end
    end
  end

  def hydrate_text(text) when is_binary(text) do
    markdown_y_state_as_update(text) || plain_text_y_state_as_update(text) ||
      empty_y_state_as_update()
  end

  def hydrate_text(_), do: empty_y_state_as_update()

  def update_text(current_y_state_as_update, text) when is_binary(text) do
    current_y_state_as_update
    |> doc_from_y_state_as_update()
    |> rewrite_doc_text(text)
  end

  def update_text(_current_y_state_as_update, text), do: hydrate_text(text)

  def empty_y_state_as_update do
    y_doc = Doc.new()
    fragment = Doc.get_xml_fragment(y_doc, @fragment_name)

    :ok = XmlFragment.push(fragment, XmlElementPrelim.new("paragraph", [], %{}))

    case Yex.encode_state_as_update(y_doc) do
      {:ok, update} -> Base.encode64(update)
      {:error, _reason} -> ""
    end
  end

  defp markdown_y_state_as_update(text) do
    with {:ok, markdown} <- parse_markdown(text),
         {:ok, y_state_as_update} <- markdown_to_y_state_as_update(markdown) do
      y_state_as_update
    else
      _ -> nil
    end
  end

  defp plain_text_y_state_as_update("") do
    empty_y_state_as_update()
  end

  defp plain_text_y_state_as_update(text) when is_binary(text) do
    y_doc = Doc.new()
    fragment = Doc.get_xml_fragment(y_doc, @fragment_name)

    case insert_plain_text_paragraph(fragment, text) do
      :ok ->
        case Yex.encode_state_as_update(y_doc) do
          {:ok, update} -> Base.encode64(update)
          {:error, _reason} -> nil
        end

      :error ->
        nil
    end
  end

  defp parse_markdown(text) do
    {:ok, MDEx.parse_document!(text, plugins: [MDExGFM])}
  rescue
    _ -> :error
  end

  defp doc_from_y_state_as_update(current_y_state_as_update)
       when is_binary(current_y_state_as_update) do
    y_doc = Doc.new()

    with {:ok, update} <- Base.decode64(current_y_state_as_update),
         :ok <- Yex.apply_update(y_doc, update) do
      y_doc
    else
      _ -> Doc.new()
    end
  end

  defp doc_from_y_state_as_update(_), do: Doc.new()

  defp rewrite_doc_text(y_doc, text) do
    fragment = Doc.get_xml_fragment(y_doc, @fragment_name)

    with :ok <- clear_fragment(fragment),
         :ok <- populate_fragment(fragment, text),
         {:ok, update} <- Yex.encode_state_as_update(y_doc) do
      Base.encode64(update)
    else
      _ -> hydrate_text(text)
    end
  end

  defp clear_fragment(fragment) do
    case XmlFragment.length(fragment) do
      0 -> :ok
      length when is_integer(length) and length > 0 -> XmlFragment.delete(fragment, 0, length)
      _ -> :error
    end
  end

  defp populate_fragment(fragment, text) do
    case parse_markdown(text) do
      {:ok, markdown} ->
        case insert_nodes(fragment, markdown.nodes) do
          {:ok, inserted_count} when inserted_count > 0 -> :ok
          _ -> insert_plain_text_paragraph(fragment, text)
        end

      :error ->
        insert_plain_text_paragraph(fragment, text)
    end
  end

  defp insert_plain_text_paragraph(fragment, text) do
    prelim = XmlElementPrelim.new("paragraph", plain_text_children(text), %{})

    case XmlFragment.push(fragment, prelim) do
      :ok -> :ok
      :error -> :error
    end
  end

  defp plain_text_children(text) do
    text
    |> String.split("\n", trim: false)
    |> Enum.with_index()
    |> Enum.flat_map(fn {segment, index} ->
      prefix =
        if index == 0 do
          []
        else
          [XmlElementPrelim.new("hardbreak", [], %{"isInline" => false})]
        end

      prefix ++ [XmlTextPrelim.from(segment)]
    end)
  end

  defp markdown_to_y_state_as_update(%MDEx.Document{nodes: nodes}) do
    y_doc = Doc.new()
    fragment = Doc.get_xml_fragment(y_doc, @fragment_name)

    case insert_nodes(fragment, nodes) do
      {:ok, inserted_count} when inserted_count > 0 ->
        case Yex.encode_state_as_update(y_doc) do
          {:ok, update} -> {:ok, Base.encode64(update)}
          {:error, _reason} -> :error
        end

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp insert_nodes(fragment, nodes) do
    Enum.reduce_while(nodes, {:ok, 0}, fn node, {:ok, count} ->
      case node_to_prelim(node) do
        nil ->
          {:cont, {:ok, count}}

        prelim ->
          case XmlFragment.push(fragment, prelim) do
            :ok -> {:cont, {:ok, count + 1}}
            :error -> {:halt, :error}
          end
      end
    end)
  end

  defp node_to_prelim(%MDEx.Paragraph{nodes: nodes}) do
    XmlElementPrelim.new("paragraph", inline_children_to_prelims(nodes), %{})
  end

  defp node_to_prelim(%MDEx.Heading{nodes: nodes, level: level}) do
    XmlElementPrelim.new("heading", inline_children_to_prelims(nodes), %{
      "level" => level,
      "id" => ""
    })
  end

  defp node_to_prelim(%MDEx.BlockQuote{nodes: nodes}) do
    XmlElementPrelim.new("blockquote", block_children_to_prelims(nodes), %{})
  end

  defp node_to_prelim(%MDEx.CodeBlock{literal: literal, info: info}) do
    XmlElementPrelim.new(
      "code_block",
      [XmlTextPrelim.from(literal || "")],
      %{"language" => info || ""}
    )
  end

  defp node_to_prelim(%MDEx.List{nodes: nodes, list_type: list_type, start: start}) do
    tag = if list_type == :ordered, do: "ordered_list", else: "bullet_list"

    attrs =
      if list_type == :ordered,
        do: %{"order" => start || 1, "spread" => false},
        else: %{"spread" => false}

    XmlElementPrelim.new(tag, block_children_to_prelims(nodes), attrs)
  end

  defp node_to_prelim(%MDEx.ListItem{nodes: nodes}) do
    XmlElementPrelim.new("list_item", block_children_to_prelims(nodes), %{})
  end

  defp node_to_prelim(%MDEx.TaskItem{nodes: nodes, checked: checked}) do
    XmlElementPrelim.new(
      "list_item",
      block_children_to_prelims(nodes),
      %{"checked" => checked}
    )
  end

  defp node_to_prelim(%MDEx.ThematicBreak{}) do
    XmlElementPrelim.empty("hr")
  end

  defp node_to_prelim(%MDEx.LineBreak{}) do
    XmlElementPrelim.new("hardbreak", [], %{"isInline" => false})
  end

  defp node_to_prelim(_), do: nil

  defp block_children_to_prelims(nodes) do
    Enum.flat_map(nodes, fn
      %MDEx.Paragraph{} = node -> [node_to_prelim(node)]
      %MDEx.Heading{} = node -> [node_to_prelim(node)]
      %MDEx.BlockQuote{} = node -> [node_to_prelim(node)]
      %MDEx.CodeBlock{} = node -> [node_to_prelim(node)]
      %MDEx.List{} = node -> [node_to_prelim(node)]
      %MDEx.ListItem{} = node -> [node_to_prelim(node)]
      %MDEx.TaskItem{} = node -> [node_to_prelim(node)]
      %MDEx.ThematicBreak{} = node -> [node_to_prelim(node)]
      %MDEx.LineBreak{} = node -> [node_to_prelim(node)]
      _ -> []
    end)
  end

  defp inline_children_to_prelims(nodes, marks \\ %{}) do
    Enum.flat_map(nodes, fn
      %MDEx.Text{literal: literal} ->
        text_delta(literal, marks)

      %MDEx.Code{literal: literal} ->
        text_delta(literal, Map.put(marks, "inlineCode", %{}))

      %MDEx.Strong{nodes: children} ->
        inline_children_to_prelims(children, Map.put(marks, "strong", %{"marker" => "*"}))

      %MDEx.Emph{nodes: children} ->
        inline_children_to_prelims(children, Map.put(marks, "emphasis", %{"marker" => "*"}))

      %MDEx.Strikethrough{nodes: children} ->
        inline_children_to_prelims(children, Map.put(marks, "strike_through", %{}))

      %MDEx.Link{nodes: children, url: url, title: title} ->
        inline_children_to_prelims(
          children,
          Map.put(marks, "link", %{"href" => url, "title" => title})
        )

      %MDEx.SoftBreak{} ->
        [XmlElementPrelim.new("hardbreak", [], %{"isInline" => false})]

      %MDEx.LineBreak{} ->
        [XmlElementPrelim.new("hardbreak", [], %{"isInline" => false})]

      _ ->
        []
    end)
  end

  defp text_delta("", _marks), do: []

  defp text_delta(literal, marks) when is_binary(literal) do
    attrs = if map_size(marks) == 0, do: %{}, else: marks
    [XmlTextPrelim.from([%{insert: literal, attributes: attrs}])]
  end
end
