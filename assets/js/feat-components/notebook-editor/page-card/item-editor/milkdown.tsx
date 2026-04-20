import React, { memo, useCallback, useEffect, useRef, useState } from "react";
import {
  Milkdown,
  MilkdownProvider,
  useEditor,
  useInstance,
} from "@milkdown/react";
import { Editor, editorViewOptionsCtx, rootCtx } from "@milkdown/kit/core";
import {
  CollabService,
  collab,
  collabServiceCtx,
} from "@milkdown/plugin-collab";
import { trailing } from "@milkdown/kit/plugin/trailing";
import { commonmark } from "@milkdown/kit/preset/commonmark";
import { gfm } from "@milkdown/kit/preset/gfm";
import * as Y from "yjs";
import {
  REMOTE_Y_ORIGIN,
  decodeUpdate,
  encodeUpdate,
  readCurrentMarkdown,
} from "../../../../utils/collab";
import { useItemEditorKeyboard } from "./keyboard";
import type {
  NotebookItem,
  NotebookPage,
} from "../../../../contexts/notebook-editor-context";
import { useFocusControl } from "./milkdown/use-focus-control";

interface MilkdownItemEditorProps {
  page: NotebookPage;
  item: NotebookItem;
  itemIndex: number;
  onChange: (text: string, yStateAsUpdate: string) => void;
}

interface EditorRuntime {
  editor: Editor;
  collabService: CollabService;
  yDoc: Y.Doc;
}

function MilkdownItemEditorSurface(
  props: MilkdownItemEditorProps & {
    onMilkdownResetNeeded: () => void;
  },
) {
  const [loading, get] = useInstance();

  const propsRef = useRef(props);
  propsRef.current = props;

  const refs = useRef<EditorRuntime | null>(null);

  const getCurrentMarkdown = useCallback(() => {
    const editor = refs.current?.editor;
    if (!editor) {
      return propsRef.current.item.text;
    }

    return readCurrentMarkdown(editor);
  }, []);

  const pendingArrowUpToFrontRef = useRef(false);
  const handleKeyDown = useItemEditorKeyboard({
    page: props.page,
    item: props.item,
    itemIndex: props.itemIndex,
    getCurrentMarkdown,
    pendingArrowUpToFrontRef,
  });
  useFocusControl({
    loading,
    get,
    pageId: props.page.id,
    itemId: props.item.id,
    pendingArrowUpToFrontRef,
  });

  useEditor((root) =>
    Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, root);
        ctx.set(editorViewOptionsCtx, {
          editable: () => true,
          attributes: {
            class:
              "field-sizing-content min-h-8 w-full whitespace-pre-wrap border-0 border-b border-base-content/30 bg-transparent px-1.5 py-1 text-sm leading-6 text-inherit outline-hidden transition focus:border-primary",
          },
          handleKeyDown,
        });
      })
      .use(commonmark)
      .use(gfm)
      .use(collab)
      .use(trailing),
  );

  useEffect(() => {
    const editor = loading ? undefined : get();
    if (!editor || refs.current) {
      return;
    }

    const yDoc = new Y.Doc();
    Y.applyUpdate(
      yDoc,
      decodeUpdate(props.item.yStateAsUpdate),
      REMOTE_Y_ORIGIN,
    );

    yDoc.on("update", (_update: Uint8Array, origin: unknown) => {
      if (origin === REMOTE_Y_ORIGIN) return;
      queueMicrotask(() => {
        if (!refs.current) return;
        propsRef.current.onChange(
          getCurrentMarkdown(),
          encodeUpdate(Y.encodeStateAsUpdate(refs.current.yDoc)),
        );
      });
    });

    editor.action((ctx) => {
      const collabService = ctx.get(collabServiceCtx)!;
      collabService.bindDoc(yDoc).connect();

      refs.current = {
        editor,
        collabService,
        yDoc,
      };
    });

    return () => {
      propsRef.current.onMilkdownResetNeeded();
    };
  }, [get, loading, getCurrentMarkdown]);

  useEffect(() => {
    if (!refs.current) return;

    Y.applyUpdate(
      refs.current.yDoc,
      decodeUpdate(props.item.yStateAsUpdate),
      REMOTE_Y_ORIGIN,
    );
  }, [props.item.yStateAsUpdate]);

  return <Milkdown />;
}

export const MilkdownItemEditor = memo(function MilkdownItemEditor(
  props: MilkdownItemEditorProps,
) {
  const [key, setKey] = useState(1);
  return (
    <MilkdownProvider key={key}>
      <MilkdownItemEditorSurface
        {...props}
        onMilkdownResetNeeded={() => {
          console.debug(
            "MilkdownItemEditor: performing workaround to reset milkdown MilkdownProvider with collabService",
          );
          setKey((k) => k + 1);
        }}
      />
    </MilkdownProvider>
  );
});
