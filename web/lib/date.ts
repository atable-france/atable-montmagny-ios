export function mondayOf(input = new Date()) {
  const date = new Date(Date.UTC(input.getUTCFullYear(), input.getUTCMonth(), input.getUTCDate()));
  const day = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() - day + 1);
  return date.toISOString().slice(0, 10);
}

export function weekDates(monday: string) {
  const start = new Date(`${monday}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(monday) || Number.isNaN(+start) || start.toISOString().slice(0, 10) !== monday || start.getUTCDay() !== 1) throw new Error("La date doit être un lundi.");
  return Array.from({ length: 5 }, (_, index) => {
    const date = new Date(+start + index * 86_400_000);
    return date.toISOString().slice(0, 10);
  });
}
