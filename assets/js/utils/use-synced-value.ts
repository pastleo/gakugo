import { useEffect, useState } from "react";

export function useSyncedValue(value: string) {
  const [draft, setDraft] = useState(value);

  useEffect(() => {
    setDraft((current) => (current === value ? current : value));
  }, [value]);

  return [draft, setDraft] as const;
}
