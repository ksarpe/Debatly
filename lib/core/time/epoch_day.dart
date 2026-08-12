/// The calendar date of [moment] — in the zone [moment] itself is expressed in
/// (device-local for a `DateTime.now()`) — as a day index: days since
/// 1970-01-01.
///
/// Used by the coarse day-based cooldowns (review ask, secure-streak nudge),
/// where "a week later" means seven local calendar days.
///
/// The local calendar date is mapped onto UTC BEFORE subtracting, so the index
/// is exact. Subtracting the UTC epoch from a LOCAL midnight (the previous
/// per-file implementations) left the UTC offset inside the difference, and a
/// DST change that moves the offset across zero (e.g. GMT↔BST) then truncated
/// differently on either side — a cooldown could read one day short or long.
int epochDay(DateTime moment) => DateTime.utc(
  moment.year,
  moment.month,
  moment.day,
).difference(DateTime.utc(1970)).inDays;
