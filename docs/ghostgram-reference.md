# GhostGram behavior reference

Reference: https://github.com/AyuGram/AyuGramDesktop
Revision inspected: 0f2a31bb420de98f331990432265b131b8d836b5 (dev).
AyuGram Desktop is distributed under GPL-3.0; its upstream copyright and license remain with its authors.
This fork retains Telegram-iOS's existing license. The new implementation is Swift code adapted to
Telegram-iOS's network, state replay and presentation APIs; it is not a binary port of the C++ client.

Behavior studied: ayu/ayu_worker.cpp, ayu/ayu_settings.cpp, ayu/utils/telegram_helpers.cpp,
api/api_updates.cpp, api/api_send_progress.cpp, data/data_message_reactions.cpp,
data/data_histories.cpp, data/data_stories.cpp, ayu/data/messages_storage.cpp.

Deliberate differences requested by the owner: GhostGram branding; RAM-only deletion/edit previews
cleared by process termination; only app icons in Appearance; no disk archive or unrelated Ayu categories.
Local Premium overrides EnginePeer premium presentation checks only for retained signed-in account IDs,
and unlocks premium icon variants. It never rewrites TelegramUser flags or grants server entitlements.
Not every premium function is client-only; server-backed features still require a real subscription.
