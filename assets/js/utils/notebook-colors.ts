import paletteJson from "../../../priv/notebook_colors.json";

export type NotebookColorRole = "foreground" | "background";

export interface NotebookColorDefinition {
  name: string;
  label: string;
  light: {
    foreground: string;
    background: string;
  };
  dark: {
    foreground: string;
    background: string;
  };
}

const palette = paletteJson as NotebookColorDefinition[];

export const NOTEBOOK_COLOR_PALETTE = palette;
export const NOTEBOOK_COLOR_NAMES = palette.map((color) => color.name);
export type NotebookColorName = (typeof NOTEBOOK_COLOR_NAMES)[number];

const NOTEBOOK_COLOR_LOOKUP = new Map(
  NOTEBOOK_COLOR_PALETTE.map((color) => [color.name, color]),
);

export function isNotebookColorName(
  value: unknown,
): value is NotebookColorName {
  return typeof value === "string" && NOTEBOOK_COLOR_LOOKUP.has(value);
}

export function notebookItemTextColorClass(
  name: NotebookColorName | null | undefined,
) {
  return name ? `notebook-item-text-${name}` : undefined;
}

export function notebookItemBackgroundColorClass(
  name: NotebookColorName | null | undefined,
) {
  return name ? `notebook-item-background-${name}` : undefined;
}

export function notebookColorSwatchClass(
  name: NotebookColorName,
  role: NotebookColorRole,
) {
  return `notebook-color-swatch-${name}-${role}`;
}
