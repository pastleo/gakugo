import React, { memo } from "react";
import type {
  NotebookItem,
  NotebookPage,
} from "../../../contexts/notebook-editor-context";
import { useNotebookEditor } from "../../../contexts/notebook-editor-context";
import {
  notebookItemBackgroundColorClass,
  notebookItemTextColorClass,
} from "../../../utils/notebook-colors";
import { isDebugEnabled } from "../../../utils/debug";
import { DebugSetTextButton } from "./item-editor/debug-set-text-btn";
import { MilkdownItemEditor } from "./item-editor/milkdown";
import { ItemEditorOptionsMenu } from "./item-editor/options-menu";
import { useItemEditorDrag } from "./item-editor/use-item-editor-drag";

interface ItemEditorProps {
  page: NotebookPage;
  item: NotebookItem;
  itemIndex: number;
}

export const ItemEditor = memo(function ItemEditor({
  page,
  item,
  itemIndex,
}: ItemEditorProps) {
  const { client } = useNotebookEditor();
  const showDebugSetTextButton = isDebugEnabled();

  const {
    isDropBefore,
    isDropAfter,
    isDropAsChild,
    rowClassName,
    handleDragStart,
    handleDragEnd,
    handleRowDragOver,
    handleRowDragLeave,
    handleRowDrop,
  } = useItemEditorDrag({ page, item });

  return (
    <li
      id={`react-notebook-item-${page.id}-${item.id}`}
      data-react-item-id={item.id}
      style={{ paddingLeft: `${item.depth * 1.25}rem` }}
      onDragOver={handleRowDragOver}
      onDragLeave={handleRowDragLeave}
      onDrop={handleRowDrop}
      className={rowClassName}
    >
      {isDropBefore ? (
        <div className="pointer-events-none absolute inset-x-2 top-0 z-10 h-0.5 rounded-full bg-primary" />
      ) : null}

      <div
        className={[
          "group rounded-2xl px-1 py-0.5",
          notebookItemBackgroundColorClass(item.backgroundColor),
        ]
          .filter(Boolean)
          .join(" ")}
      >
        <div className="flex items-start gap-2">
          <div className="mt-1" title="Item options">
            <ItemEditorOptionsMenu
              page={page}
              item={item}
              buttonProps={{
                draggable: true,
                onDragStart: handleDragStart,
                onDragEnd: handleDragEnd,
                title: "Drag to move item or click for options",
              }}
            />
          </div>

          <div
            className={[
              "flex min-w-56 grow items-start gap-2",
              notebookItemTextColorClass(item.textColor),
            ]
              .filter(Boolean)
              .join(" ")}
          >
            <div className="grow">
              <MilkdownItemEditor
                page={page}
                item={item}
                itemIndex={itemIndex}
                onChange={(text, yStateAsUpdate) => {
                  client.textCollabUpdate(page, item.id, text, yStateAsUpdate);
                }}
              />
            </div>

            {showDebugSetTextButton ? (
              <DebugSetTextButton page={page} item={item} />
            ) : null}
          </div>
        </div>
      </div>

      {isDropAfter || isDropAsChild ? (
        <div
          className={[
            "pointer-events-none absolute bottom-0 z-10 h-0.5 rounded-full bg-primary",
            isDropAsChild ? "left-12 right-2" : "inset-x-2",
          ].join(" ")}
        />
      ) : null}
    </li>
  );
});
