import React, { forwardRef, useLayoutEffect, useRef } from "react";

function syncTextareaHeight(element: HTMLTextAreaElement | null) {
  if (!element) return;

  const previousHeight = element.style.height;
  element.style.height = "auto";
  const nextHeight = `${element.scrollHeight}px`;

  element.style.height =
    previousHeight === nextHeight ? previousHeight : nextHeight;
}

export interface AutoResizeTextareaProps
  extends React.TextareaHTMLAttributes<HTMLTextAreaElement> {
  className?: string;
}

export const AutoResizeTextarea = forwardRef<
  HTMLTextAreaElement,
  AutoResizeTextareaProps
>(function AutoResizeTextarea({ className = "", value, ...props }, ref) {
  const innerRef = useRef<HTMLTextAreaElement | null>(null);

  useLayoutEffect(() => {
    syncTextareaHeight(innerRef.current);
  }, [value]);

  return (
    <textarea
      {...props}
      ref={(node) => {
        innerRef.current = node;

        if (typeof ref === "function") {
          ref(node);
        } else if (ref) {
          (ref as React.MutableRefObject<HTMLTextAreaElement | null>).current =
            node;
        }
      }}
      rows={1}
      value={value}
      className={className}
    />
  );
});
