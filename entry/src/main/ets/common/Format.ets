export function displayYear(value: string): string {
  const found = value.match(/\b(?:18|19|20)\d{2}\b/);
  return found ? `${found[0]} 年` : (value || '年份未知');
}

export function displayCount(value: number | null): string {
  return value === null ? '—' : `${value}`;
}

export function displayText(value?: string): string {
  return value && value.trim() ? value.trim() : '暂无';
}

export function formatLibraryDateTime(value?: string): string {
  if (!value) { return ''; }
  const match = /(\d{4})[-/](\d{1,2})[-/](\d{1,2})[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?/.exec(value);
  if (!match) { return value.trim(); }
  const pad = (part: string): string => part.padStart(2, '0');
  return `${match[1]}-${pad(match[2])}-${pad(match[3])} ` +
    `${pad(match[4])}:${pad(match[5])}:${pad(match[6] || '0')}`;
}
