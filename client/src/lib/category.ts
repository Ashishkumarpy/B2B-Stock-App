export function unslugifyCategory(value: string): string {
  return value
    .trim()
    .replace(/[-_]+/g, ' ')
    .replace(/\s+/g, ' ');
}

export function titleCase(value: string): string {
  return value
    .split(' ')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

// Keep this aligned with the client nav slugs.
const CATEGORY_SLUG_MAP: Record<string, string> = {
  bags: 'Bags',
  'card-holders': 'Card Holders',
  electronics: 'Electronics',
  'gift-sets': 'Gift Sets & Combos',
  diwali: 'Diwali Catalogue',
  'id-cards': 'ID Cards',
  keychains: 'Keychains & Badge Reels',
  'water-bottles': 'Water Bottles',
  mugs: 'Mugs',
  notebooks: 'Notebooks & Diaries',
};

export function categorySlugToName(slugOrName: string): string {
  const key = slugOrName.trim().toLowerCase();
  return CATEGORY_SLUG_MAP[key] ?? titleCase(unslugifyCategory(slugOrName));
}

export function slugifyCategoryName(name: string): string {
  const normalized = name.trim().toLowerCase();
  for (const [slug, displayName] of Object.entries(CATEGORY_SLUG_MAP)) {
    if (displayName.toLowerCase() === normalized) return slug;
  }

  return normalized
    .replace(/&/g, 'and')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}
