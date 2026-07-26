// Mirrors the backend's `can_duplicate_into?` check so the entry points
// (sidebar link, picker page, topic-admin menu button) simply don't render
// for users who couldn't use them anyway. The category half of the check is
// handled separately by reusing CategoryChooser's default `FULL` permission
// filter, and by checking `category.canCreateTopic` directly.
export function canDuplicateEvents(currentUser, siteSettings) {
  if (!currentUser) {
    return false;
  }

  // `enabled_site_setting :event_duplicator_enabled` gates the plugin's
  // backend routes/hooks, but does nothing to a JS bundle that's already
  // loaded -- since the setting is `client: true` specifically so it takes
  // effect live (without a restart), the frontend has to check it itself
  // rather than relying solely on the backend being gone.
  if (!siteSettings.event_duplicator_enabled) {
    return false;
  }

  // Mirrors the backend's `can_create_calendar_event?` -- discourse-calendar
  // serializes this directly onto current_user (see e.g. its own
  // add-events-create-topic-button.js), so this reads discourse-calendar's
  // own answer rather than reimplementing its `discourse_post_event_allowed_on_groups`
  // group-membership check here.
  if (!currentUser.can_create_discourse_post_event) {
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
