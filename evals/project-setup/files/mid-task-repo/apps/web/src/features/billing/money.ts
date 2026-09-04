// Display formatting for money amounts held as integer minor units.
export function formatCurrency(cents: number, currency: string): string {
  return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(cents / 100);
}
