import type { SectionData, SplashData } from "./discovery.ts";

export interface SplashRenderOptions {
  gap?: number;
}

export interface PlainTheme {
  fg(color: string, text: string): string;
  bold(text: string): string;
}

const PI_ART = [
  "██████╗ ██╗",
  "██╔══██╗██║",
  "██████╔╝██║",
  "██╔═══╝ ██║",
  "██║     ██║",
  "╚═╝     ╚═╝",
];

export function renderSplash(
  data: SplashData,
  width: number,
  theme?: PlainTheme,
  options: SplashRenderOptions = {},
): string[] {
  if (width <= 0) return [];

  const gap = options.gap ?? 2;
  let plain: string[];

  if (width < 58) {
    plain = renderSingleColumn(data, width, "mini");
  } else if (width < 96) {
    plain = renderSingleColumn(data, width, "compact");
  } else {
    const heroWidth = clamp(Math.floor(width * 0.38), 38, 50);
    const detailsWidth = width - heroWidth - gap;
    plain = joinColumns(
      renderHeroBox(data, heroWidth, width >= 124 ? "full" : "compact", 17),
      renderDetails(data, detailsWidth, width >= 124 ? "full" : "compact"),
      heroWidth,
      detailsWidth,
      gap,
    );
  }

  const bounded = plain.map((line) => truncate(line, width));
  return theme ? applyTheme(bounded, theme) : bounded;
}

export function renderSingleColumn(
  data: SplashData,
  width: number,
  density: "mini" | "compact" | "full",
): string[] {
  const hero = renderHeroBox(data, width, density);
  const sections = [
    data.sections.context,
    data.sections.skills,
    data.sections.prompts,
    data.sections.extensions,
  ];

  return [
    ...hero,
    "",
    ...sections.flatMap((section, index) => [
      ...(index === 0 ? [] : [""]),
      ...renderSectionBox(section, width, density),
    ]),
  ];
}

function renderDetails(data: SplashData, width: number, density: "compact" | "full"): string[] {
  const gap = 2;
  const leftWidth = Math.floor((width - gap) / 2);
  const rightWidth = width - gap - leftWidth;

  const firstRow = joinColumns(
    renderSectionBox(data.sections.context, leftWidth, density, 7),
    renderSectionBox(data.sections.skills, rightWidth, density, 7),
    leftWidth,
    rightWidth,
    gap,
  );
  const secondRow = joinColumns(
    renderSectionBox(data.sections.prompts, leftWidth, density, 7),
    renderSectionBox(data.sections.extensions, rightWidth, density, 7),
    leftWidth,
    rightWidth,
    gap,
  );

  return [...firstRow, "", ...secondRow];
}

export function renderHeroBox(
  data: SplashData,
  width: number,
  density: "mini" | "compact" | "full",
  minBodyLines = 0,
): string[] {
  const art = density === "mini" ? ["██████╗ ██╗", "██╔══██╗██║", "██████╔╝██║", "██║     ██║"] : PI_ART;
  const innerWidth = Math.max(1, width - 4);
  const lines = [
    ...art.map((line) => center(line, innerWidth)),
    "",
    center("coding agent", innerWidth),
    "",
    `model  ${data.modelLabel}`,
    `cwd    ${data.cwdLabel}`,
  ];

  if (data.version) lines.push(`build  v${data.version}`);
  lines.push(
    `context:    ${data.sections.context.count} loaded`,
    `skills:     ${data.sections.skills.count} loaded`,
    `prompts:    ${data.sections.prompts.count} loaded`,
    `extensions: ${data.sections.extensions.count} loaded`,
  );

  if (lines.length < minBodyLines) {
    const missing = minBodyLines - lines.length;
    const before = Math.floor(missing / 2);
    const after = missing - before;
    lines.unshift(...Array.from({ length: before }, () => ""));
    lines.push(...Array.from({ length: after }, () => ""));
  }

  return drawBox("", lines, width, 1);
}

export function renderSectionBox(
  section: SectionData,
  width: number,
  density: "mini" | "compact" | "full",
  minBodyLines = 0,
): string[] {
  const innerWidth = Math.max(1, width - 4);
  const maxItems = density === "full" ? 12 : density === "compact" ? 10 : 3;
  const shown = compactList(section.items, maxItems);
  const body = wrapText(shown.join("  ·  "), innerWidth);
  const maxLines = Math.max(minBodyLines, density === "full" ? 7 : density === "compact" ? 6 : 2);
  const visible = body.slice(0, maxLines);
  while (visible.length < minBodyLines) visible.push("");
  return drawBox(section.title, visible, width);
}

export function summarize(
  section: SectionData,
  density: "mini" | "compact" | "full",
  noun = "item",
): string {
  const top = compactList(section.items, density === "full" ? 4 : density === "compact" ? 3 : 2);
  const base = `${section.count} ${noun}${section.count === 1 ? "" : "s"}`;
  return top.length > 0 ? `${base} · ${top.join(", ")}` : base;
}

export function compactList(items: readonly string[], maxItems: number): string[] {
  if (items.length <= maxItems) return [...items];
  const shown = items.slice(0, Math.max(0, maxItems - 1));
  shown.push(`+${items.length - shown.length} more`);
  return shown;
}

export function drawBox(title: string, bodyLines: readonly string[], width: number, padding = 1): string[] {
  const safeWidth = Math.max(4, width);
  const innerWidth = safeWidth - 2;
  const contentWidth = Math.max(1, innerWidth - padding * 2);
  let top = `╭${"─".repeat(innerWidth)}╮`;

  if (title) {
    const label = ` ${title} `;
    top = `╭${label}${"─".repeat(Math.max(0, innerWidth - label.length))}╮`;
  }

  const body = bodyLines.length > 0 ? bodyLines : [""];
  return [
    truncate(top, safeWidth),
    ...body.map((line) => `│${" ".repeat(padding)}${pad(truncate(line, contentWidth), contentWidth)}${" ".repeat(padding)}│`),
    `╰${"─".repeat(innerWidth)}╯`,
  ];
}

export function joinColumns(
  left: readonly string[],
  right: readonly string[],
  leftWidth: number,
  rightWidth: number,
  gap: number,
): string[] {
  const rows = Math.max(left.length, right.length);
  const lines: string[] = [];
  for (let i = 0; i < rows; i += 1) {
    const l = pad(left[i] || "", leftWidth);
    const r = pad(right[i] || "", rightWidth);
    lines.push(`${l}${" ".repeat(gap)}${r}`);
  }
  return lines;
}

export function wrapText(text: string, width: number): string[] {
  if (width <= 1) return [text.slice(0, Math.max(0, width))];
  const words = text.split(/\s+/).filter(Boolean);
  if (words.length === 0) return [""];

  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length <= width) {
      current = candidate;
    } else if (!current) {
      lines.push(truncate(word, width));
    } else {
      lines.push(current);
      current = word.length <= width ? word : truncate(word, width);
    }
  }
  if (current) lines.push(current);
  return lines;
}

export function pad(text: string, width: number): string {
  if (text.length >= width) return text.slice(0, width);
  return text + " ".repeat(width - text.length);
}

export function truncate(text: string, width: number): string {
  if (width <= 0) return "";
  if (text.length <= width) return text;
  if (width === 1) return "…";
  return text.slice(0, width - 1) + "…";
}

export function center(text: string, width: number): string {
  const clipped = truncate(text, width);
  const left = Math.max(0, Math.floor((width - clipped.length) / 2));
  return " ".repeat(left) + clipped;
}

function applyTheme(lines: readonly string[], theme: PlainTheme): string[] {
  const artColors = ["mdLink", "accent", "accent", "success", "success", "mdLink"];
  let artLine = 0;

  return lines.map((line) => {
    if (!line) return line;

    let styled = line.replace(
      /( Context | Skills | Prompts | Extensions )/g,
      (title) => theme.bold(theme.fg("accent", title)),
    );

    styled = styled.replace(/[█╔╗╚╝═║]+(?: [█╔╗╚╝═║]+)*/g, (art) => {
      const color = artColors[Math.min(artLine, artColors.length - 1)];
      artLine += 1;
      return theme.bold(theme.fg(color, art));
    });

    if (styled.includes("coding agent")) {
      styled = styled.replace("coding agent", theme.fg("muted", "coding agent"));
    }

    return styled.replace(/[╭╮╰╯│─]+/g, (border) => theme.fg("dim", border));
  });
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
