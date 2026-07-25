// Mirrors the backend's `can_duplicate_into?` check so the entry points
// (sidebar link, picker page, topic-admin menu button) simply don't render
// for users who couldn't use them anyway. The category half of the check is
// handled separately by reusing CategoryChooser's default `FULL` permission
// filter, and by checking `category.canCreateTopic` directly.
export function canDuplicateEvents(currentUser, siteSettings) {
  if (!currentUser) {
    return false;
  }

  const allowedGroupIds = (siteSettings.event_duplicator_allowed_groups || "")
    .split("|")
    .filter(Boolean)
    .map(Number);

  if (!allowedGroupIds.length) {
    return false;
  }

  const userGroupIds = (currentUser.groups || []).map((group) => group.id);
  return allowedGroupIds.some((id) => userGroupIds.includes(id));
}
