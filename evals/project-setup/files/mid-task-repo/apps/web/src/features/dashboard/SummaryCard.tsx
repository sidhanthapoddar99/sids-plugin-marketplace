// Dashboard summary tile. Shows the month-to-date invoiced total.
export function SummaryCard({ totalCents, currency }: { totalCents: number; currency: string }) {
  // TODO: this needs the same money formatting the billing feature already has.
  return <div>{totalCents}</div>;
}
