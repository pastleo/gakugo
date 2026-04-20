import React, { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import {
  NotebookEditor,
  type ApplyIntentReply,
  type NotebookInitialPages,
} from "./feat-components/notebook-editor";

function parseInitialPagesJson(
  value: string | undefined,
): NotebookInitialPages {
  try {
    const parsed = JSON.parse(value || "{}");

    if (Array.isArray(parsed)) {
      return { unitId: null, pages: parsed };
    }

    if (parsed && Array.isArray(parsed.pages)) {
      return { unitId: parsed.unit_id ?? null, pages: parsed.pages };
    }

    return { unitId: null, pages: [] };
  } catch {
    return { unitId: null, pages: [] };
  }
}

interface LiveViewHookContext {
  el: HTMLElement;
  root?: { render(node: unknown): void; unmount(): void };
  addReactUpdateListener: (
    callback: (payload: unknown) => void,
  ) => void | (() => void);
  applyIntent?: (intent: Record<string, unknown>) => Promise<ApplyIntentReply>;
  handleEvent(event: string, callback: (payload: unknown) => void): unknown;
  pushEvent(
    event: string,
    payload: Record<string, unknown>,
    callback: (reply: unknown) => void,
  ): void;
}

export const NotebookEditorPhxHook = {
  mounted() {
    const hook = this as unknown as LiveViewHookContext;

    hook.root = createRoot(hook.el);

    const initialPages = parseInitialPagesJson(
      hook.el.dataset.initialPagesJson,
    );

    hook.addReactUpdateListener = (callback: (payload: unknown) => void) =>
      void hook.handleEvent("react:update", (payload: unknown) => {
        if (payload && typeof payload === "object" && "update" in payload) {
          callback((payload as { update?: unknown }).update);
          return;
        }

        callback(payload);
      });

    hook.applyIntent = (intent: Record<string, unknown>) =>
      new Promise<ApplyIntentReply>((resolve) => {
        hook.pushEvent("apply_intent", intent, (reply: unknown) => {
          resolve(reply as ApplyIntentReply);
        });
      });

    hook.root.render(
      <StrictMode>
        <NotebookEditor
          initialPages={initialPages}
          addReactUpdateListener={hook.addReactUpdateListener}
          applyIntent={hook.applyIntent}
        />
      </StrictMode>,
    );
  },

  destroyed() {
    const hook = this as unknown as LiveViewHookContext;
    hook.root?.unmount();
  },
};
