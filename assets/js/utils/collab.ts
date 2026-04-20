import { Editor, serializerCtx, editorViewCtx } from "@milkdown/kit/core";

export const REMOTE_Y_ORIGIN = "milkdown-remote-sync";

export function encodeUpdate(update: Uint8Array) {
  return uint8ArrayToBase64(update);
}

export function decodeUpdate(encodedUpdate: string) {
  return base64ToUint8Array(encodedUpdate);
}

export function readCurrentMarkdown(editor: Editor) {
  return editor.action((ctx) => {
    const serializer = ctx.get(serializerCtx);
    const view = ctx.get(editorViewCtx);
    const markdown = serializer(view.state.doc);

    if (markdown.endsWith("\n") && !markdown.endsWith("\n\n")) {
      return markdown.slice(0, -1);
    }
    return markdown;
  });
}

function uint8ArrayToBase64(bytes: Uint8Array) {
  let binary = "";

  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });

  return btoa(binary);
}

function base64ToUint8Array(base64: string) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
}
