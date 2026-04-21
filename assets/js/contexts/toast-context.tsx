import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

export type ToastTone = "info" | "success" | "error";

export interface ToastOptions {
  tone?: ToastTone;
  title: string;
  description?: string;
  durationMs?: number;
}

interface ToastItem extends Required<Pick<ToastOptions, "title">> {
  id: number;
  tone: ToastTone;
  description?: string;
}

interface ToastContextValue {
  pushToast: (options: ToastOptions) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const nextToastIdRef = useRef(1);
  const timeoutIdsRef = useRef(
    new Map<number, ReturnType<typeof setTimeout>>(),
  );

  const removeToast = useCallback((id: number) => {
    const timeoutId = timeoutIdsRef.current.get(id);

    if (timeoutId) {
      clearTimeout(timeoutId);
      timeoutIdsRef.current.delete(id);
    }

    setToasts((current) => current.filter((toast) => toast.id !== id));
  }, []);

  useEffect(() => {
    return () => {
      for (const timeoutId of timeoutIdsRef.current.values()) {
        clearTimeout(timeoutId);
      }

      timeoutIdsRef.current.clear();
    };
  }, []);

  const pushToast = useCallback(
    ({
      tone = "info",
      title,
      description,
      durationMs = 2500,
    }: ToastOptions) => {
      const id = nextToastIdRef.current;
      nextToastIdRef.current += 1;

      const timeoutId = setTimeout(() => removeToast(id), durationMs);
      timeoutIdsRef.current.set(id, timeoutId);

      setToasts((current) => [...current, { id, tone, title, description }]);
    },
    [removeToast],
  );

  const value = useMemo<ToastContextValue>(() => ({ pushToast }), [pushToast]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="toast toast-top toast-end pointer-events-none fixed right-4 top-4 z-50">
        {toasts.map((toast) => (
          <div
            key={toast.id}
            role={toast.tone === "error" ? "alert" : "status"}
            className={[
              "pointer-events-auto relative min-w-72 max-w-sm rounded-2xl border px-5 py-4 shadow-lg",
              toast.tone === "success"
                ? "border-success/30 bg-success text-success-content"
                : toast.tone === "error"
                  ? "border-error/30 bg-error text-error-content"
                  : "border-base-300 bg-base-100 text-base-content",
            ].join(" ")}
          >
            <div className="pr-8">
              <div className="text-sm font-semibold">{toast.title}</div>
              {toast.description ? (
                <div className="mt-1 text-xs opacity-80">
                  {toast.description}
                </div>
              ) : null}
            </div>

            <button
              type="button"
              onClick={() => removeToast(toast.id)}
              className="absolute right-3 top-3 inline-flex size-6 items-center justify-center rounded-full text-current/80 transition hover:bg-black/10 hover:text-current"
              aria-label="Dismiss toast"
            >
              ✕
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const context = useContext(ToastContext);

  if (!context) {
    throw new Error("useToast must be used within ToastProvider");
  }

  return context;
}
