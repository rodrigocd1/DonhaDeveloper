import { LightningElement, api, track } from 'lwc';
import getMessages      from '@salesforce/apex/CommunicatorChatController.getMessages';
import getMessagesAcrossThreads from '@salesforce/apex/CommunicatorChatController.getMessagesAcrossThreads';
import getMessageCount  from '@salesforce/apex/CommunicatorChatController.getMessageCount';
import getMessageCountAcrossThreads from '@salesforce/apex/CommunicatorChatController.getMessageCountAcrossThreads';
import getMessageOffset from '@salesforce/apex/CommunicatorChatController.getMessageOffset';
import getMessageOffsetAcrossThreads from '@salesforce/apex/CommunicatorChatController.getMessageOffsetAcrossThreads';
import pollTimeline from '@salesforce/apex/CommunicatorChatController.pollTimeline';
import getAttachmentFile from '@salesforce/apex/CommunicatorChatController.getAttachmentFile';
import getMessageAttachments from '@salesforce/apex/CommunicatorChatController.getMessageAttachments';
import getMentionUserNames from '@salesforce/apex/CommunicatorChatController.getMentionUserNames';
import getThreadHistoryParticipantIds from '@salesforce/apex/CommunicatorChatController.getThreadHistoryParticipantIds';
import getThreadHistoryParticipantIdsAcrossThreads from '@salesforce/apex/CommunicatorChatController.getThreadHistoryParticipantIdsAcrossThreads';
import getThreadPresenceOverrides from '@salesforce/apex/CommunicatorChatController.getThreadPresenceOverrides';
import getSettings      from '@salesforce/apex/CommunicatorChatController.getSettings';
import { fetchAllTimelinePages } from './pollingUtils';
import Id from '@salesforce/user/Id';
import SYSTEM_AVATAR from '@salesforce/resourceUrl/communicatorSystemAvatar';
import {
    on as onSocket,
    getUsersConnectionStatus,
    isConnected as isSocketConnected
} from 'c/communicatorSocketService';

const DEFAULT_PAGE_SIZE = 20;
const SCROLL_THRESHOLD  = 80; // px from top to trigger load more
const DEFAULT_AVATAR_URL = '/img/icon/t4v35/standard/person_account_120.png';
const HISTORY_LOADING_MIN_VISIBLE_MS = 120;

export default class CommunicatorChatTimeline extends LightningElement {

    _threadId;
    _threadIds = [];
    _isConnected = false;

    @api emptyVariant = '';
    @api loadAllMessages = false;


    @api
    get threadId() { return this._threadId; }
    set threadId(val) {
        const prev = this._threadId;
        this._threadId = val;
        // When thread changes while mounted, reset and reload for the new thread
        if (val !== prev && val && this._isConnected && !this.isMultiThreadMode) {
            this._reset();
            this._loadInitial().catch(console.error);
        }
    }

    @api
    get threadIds() { return this._threadIds; }
    set threadIds(val) {
        const next = this._normalizeThreadIds(val);
        const prevKey = JSON.stringify(this._threadIds);
        const nextKey = JSON.stringify(next);
        this._threadIds = next;
        if (prevKey !== nextKey && this._isConnected) {
            this._reset();
            if (this.isMultiThreadMode || this._threadId) {
                this._loadInitial().catch(console.error);
            }
        }
    }

    @api
    get highlightMessageId() { return this._highlightMessageId; }
    set highlightMessageId(val) {
        this._highlightMessageId = val;
        if (val) this._applyHighlight(val);
    }

    @track messages       = [];
    @track isLoadingMore  = false;
    @track isLoadingMessages = false;
    @track hasMoreMessages = false;
    @track collapsedReplyParentIds = [];

    _pageSize       = DEFAULT_PAGE_SIZE;
    _currentOffset  = 0;
    _totalCount     = 0;
    _lastTimestamp  = null;
    _highlightMessageId;
    _currentUserId  = Id;
    _isSalesforcePlatformUser = false;
    _socketStatus = 'offline';
    _peerStatusMap = {};
    _presenceOverrideByThreadAndUser = {};
    _socketUnsubscribes = [];
    _threadHistoryParticipantIds = [];
    _mentionUserNameById = {};
    _parentMessageById = {};
    _derivedParentMessageById = {};
    _historyLoadingStartAt = 0;
    _historyLoadingHideTimer = null;
    _presenceOverrideLastFetchAt = 0;
    // Presence data changes rarely; re-fetch only after this interval during polling.
    // Initial load (_refreshThreadPresenceContext) always bypasses this cache.
    _PRESENCE_OVERRIDE_POLL_TTL_MS = 30000;

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Lifecycle
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    async connectedCallback() {
        this._isConnected = true;
        this._initSocketListeners();
        await this._loadConfig();
        if (this.isMultiThreadMode || this._threadId) {
            await this._loadInitial();
        }
    }

    disconnectedCallback() {
        this._isConnected = false;
        this._socketUnsubscribes.forEach(fn => fn());
        this._socketUnsubscribes = [];
        this._clearHistoryLoadingTimer();
    }

    renderedCallback() {
        this._renderMessageBodies();
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Public API
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @api
    async refresh() {
        if (!this._lastTimestamp) {
            await this._loadInitial();
        } else {
            await this._pollMessages();
        }
    }

    @api
    scrollToBottom() {
        const bottom = this.template.querySelector('.comm-timeline__bottom');
        if (bottom) bottom.scrollIntoView({ behavior: 'smooth' });
    }

    @api
    scrollToMessage(messageId) {
        this._expandReplyAncestors(messageId);
        const el = this.template.querySelector(`[data-message-id="${messageId}"]`);
        if (el) {
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            this._applyHighlight(messageId);
        }
    }

    /**
     * Navigates to a message, loading the correct page first if necessary.
     * Use this instead of scrollToMessage when the message may not be in the current page.
     */
    @api
    async navigateToMessage(messageId) {
        if (!messageId) return;
        this._highlightMessageId = messageId;
        // If the message is already rendered, just scroll
        const el = this.template.querySelector(`[data-message-id="${messageId}"]`);
        if (el) {
            this.scrollToMessage(messageId);
            return;
        }
        // Message not in DOM â€” load the page that contains it
        if (this.loadAllMessages) {
            await this._loadInitial();
            return;
        }
        this.isLoadingMore = true;
        try {
            const pos = this.isMultiThreadMode
                ? await getMessageOffsetAcrossThreads({ threadIds: this._threadIds, messageId })
                : await getMessageOffset({ threadId: this.threadId, messageId });
            if (pos < 0) return;
            const offset = Math.max(0, pos - Math.floor(this._pageSize / 2));
            const msgs = this.isMultiThreadMode
                ? await getMessagesAcrossThreads({
                    threadIds: this._threadIds,
                    pageSize: this._pageSize,
                    offsetVal: offset
                })
                : await getMessages({
                    threadId: this.threadId,
                    pageSize: this._pageSize,
                    offsetVal: offset
                });
            this.messages        = await this._enrichMessages(msgs);
            this._syncReplyCollapseState();
            this._currentOffset  = offset;
            this.hasMoreMessages = offset > 0;
            this._updateLastTimestamp();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.scrollToMessage(messageId), 100);
        } finally {
            this.isLoadingMore = false;
        }
    }

    @api
    async loadNextPage() {
        if (this.loadAllMessages) return;
        if (!this.hasMoreMessages || this.isLoadingMore) return;
        const newOffset = Math.max(0, this._currentOffset - this._pageSize);
        await this._loadPage(newOffset);
    }

    @api
    scrollToTop() {
        const el = this.template.querySelector('.comm-timeline');
        if (el) el.scrollTop = 0;
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Config
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    _reset() {
        this.messages        = [];
        this.isLoadingMore   = false;
        this.isLoadingMessages = false;
        this.hasMoreMessages = false;
        this.collapsedReplyParentIds = [];
        this._currentOffset  = 0;
        this._totalCount     = 0;
        this._lastTimestamp  = null;
        this._pollCursor = null;
        this._threadHistoryParticipantIds = [];
        this._mentionUserNameById = {};
        this._parentMessageById = {};
        this._derivedParentMessageById = {};
        this._presenceOverrideByThreadAndUser = {};
        this._presenceOverrideLastFetchAt = 0;
        this._clearHistoryLoadingTimer();
    }

    async _loadConfig() {
        try {
            const settings = await getSettings();
            if (settings.messagesPerPage > 0) this._pageSize = settings.messagesPerPage;
            this._isSalesforcePlatformUser = settings.isSalesforcePlatformUser === true;
        } catch (e) {
            // Keep defaults on failure
        }
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Data loading
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    async _loadInitial() {
        this.isLoadingMessages = true;
        this._historyLoadingStartAt = Date.now();
        try {
            this._totalCount = this.isMultiThreadMode
                ? await getMessageCountAcrossThreads({ threadIds: this._threadIds })
                : await getMessageCount({ threadId: this.threadId });
            this._startHistoryLoading();
            await this._refreshThreadPresenceContext();

            if (this.loadAllMessages) {
                const allMsgs = await this._loadAllMessages();
                this.messages = await this._enrichMessages(allMsgs);
                this._syncReplyCollapseState();
                this._currentOffset = 0;
                this.hasMoreMessages = false;
                this._updateLastTimestamp();
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    if (this._highlightMessageId) {
                        this.scrollToMessage(this._highlightMessageId);
                    } else {
                        this.scrollToBottom();
                    }
                }, 100);
                return;
            }

            if (this._highlightMessageId) {
                const pos = this.isMultiThreadMode
                    ? await getMessageOffsetAcrossThreads({
                        threadIds: this._threadIds,
                        messageId: this._highlightMessageId
                    })
                    : await getMessageOffset({
                        threadId: this.threadId,
                        messageId: this._highlightMessageId
                    });
                this._currentOffset = pos >= 0
                    ? Math.max(0, pos - Math.floor(this._pageSize / 2))
                    : Math.max(0, this._totalCount - this._pageSize);
            } else {
                this._currentOffset = Math.max(0, this._totalCount - this._pageSize);
            }

            const msgs = this.isMultiThreadMode
                ? await getMessagesAcrossThreads({
                    threadIds: this._threadIds,
                    pageSize: this._pageSize,
                    offsetVal: this._currentOffset
                })
                : await getMessages({
                    threadId: this.threadId,
                    pageSize: this._pageSize,
                    offsetVal: this._currentOffset
                });
            this.messages        = await this._enrichMessages(msgs);
            this._syncReplyCollapseState();
            this.hasMoreMessages = this._currentOffset > 0;
            this._updateLastTimestamp();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (this._highlightMessageId) {
                    this.scrollToMessage(this._highlightMessageId);
                } else {
                    this.scrollToBottom();
                }
            }, 100);
        } finally {
            this._stopHistoryLoading();
        }
    }

    _startHistoryLoading() {
        this._clearHistoryLoadingTimer();
        this.isLoadingMessages = true;
        this._historyLoadingStartAt = Date.now();
    }

    _stopHistoryLoading() {
        this._clearHistoryLoadingTimer();
        if (!this.isLoadingMessages) return;
        const elapsed = Date.now() - this._historyLoadingStartAt;
        const waitMs = HISTORY_LOADING_MIN_VISIBLE_MS - elapsed;
        if (waitMs <= 0) {
            this.isLoadingMessages = false;
            return;
        }
        this._historyLoadingHideTimer = setTimeout(() => {
            this.isLoadingMessages = false;
            this._historyLoadingHideTimer = null;
        }, waitMs);
    }

    _clearHistoryLoadingTimer() {
        if (!this._historyLoadingHideTimer) return;
        clearTimeout(this._historyLoadingHideTimer);
        this._historyLoadingHideTimer = null;
    }

    async _loadAllMessages() {
        if (!this._totalCount || this._totalCount <= 0) return [];

        const batchSize = Math.max(this._pageSize, DEFAULT_PAGE_SIZE);
        const all = [];
        let offset = 0;

        while (offset < this._totalCount) {
            const batch = this.isMultiThreadMode
                ? await getMessagesAcrossThreads({
                    threadIds: this._threadIds,
                    pageSize: batchSize,
                    offsetVal: offset
                })
                : await getMessages({
                    threadId: this.threadId,
                    pageSize: batchSize,
                    offsetVal: offset
                });

            if (!batch || batch.length === 0) break;

            all.push(...batch);
            offset += batch.length;

            if (batch.length < batchSize) break;
        }

        return all;
    }

    async _loadPage(offset) {
        if (this.isLoadingMore) return;
        this.isLoadingMore = true;
        try {
            const containerEl      = this.template.querySelector('.comm-timeline');
            const prevScrollHeight = containerEl?.scrollHeight || 0;

            const msgs = this.isMultiThreadMode
                ? await getMessagesAcrossThreads({
                    threadIds: this._threadIds,
                    pageSize: this._pageSize,
                    offsetVal: offset
                })
                : await getMessages({
                    threadId: this.threadId,
                    pageSize: this._pageSize,
                    offsetVal: offset
                });
            const enriched = await this._enrichMessages(msgs);

            // Prepend older messages
            this.messages        = [...enriched, ...this.messages];
            this._syncReplyCollapseState();
            this._currentOffset  = offset;
            this.hasMoreMessages = this._currentOffset > 0;
            await this._refreshThreadPresenceContext();
            this._refreshPresenceStates();

            // Restore scroll position after DOM update
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const newScrollHeight = containerEl?.scrollHeight || 0;
                if (containerEl) {
                    containerEl.scrollTop = newScrollHeight - prevScrollHeight;
                }
            }, 50);
        } finally {
            this.isLoadingMore = false;
        }
    }

    async _pollMessages() {
        if (this._pollCursor === null) return;
        const { messages: fetchedMessages, cursor } = await fetchAllTimelinePages({
            cursor: this._pollCursor,
            existingMessages: this.messages,
            pageSize: 50,
            fetchPage: nextCursor => pollTimeline({
                threadId: this.isMultiThreadMode ? null : this.threadId,
                threadIds: this.isMultiThreadMode ? this._threadIds : null,
                cursor: nextCursor,
                pageSize: 50
            })
        });
        await this._hydratePresenceOverrides().catch(() => {});
        if (fetchedMessages.length > 0) {
            const enriched = await this._enrichMessages(fetchedMessages);
            this.messages = [...this.messages, ...enriched];
            this._syncReplyCollapseState();
            await this._refreshThreadPresenceContext();
        }
        this._pollCursor = cursor;
        this._lastTimestamp = this.messages.length
            ? this.messages[this.messages.length - 1].SentAt__c
            : this._lastTimestamp;
        this._refreshPresenceStates();
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Handlers
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    handleScroll(event) {
        if (this.loadAllMessages) return;
        const el = event.target;
        if (el.scrollTop <= SCROLL_THRESHOLD && this.hasMoreMessages && !this.isLoadingMore) {
            const newOffset = Math.max(0, this._currentOffset - this._pageSize);
            this._loadPage(newOffset).catch(console.error);
        }
    }

    handleToggleReplies(event) {
        const parentId = event.currentTarget?.dataset?.parentId;
        if (!parentId) return;
        const collapsedSet = new Set(this.collapsedReplyParentIds || []);
        if (collapsedSet.has(parentId)) {
            collapsedSet.delete(parentId);
        } else {
            collapsedSet.add(parentId);
        }
        this.collapsedReplyParentIds = [...collapsedSet];
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Helpers
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    async _enrichMessages(msgs) {
        msgs = (msgs || []).map(m => (m && !m.Id && m.ExternalId__c ? { ...m, Id: m.ExternalId__c } : m));
        const attachmentsByMessageId = await this._loadMessageAttachments(msgs);
        await this._cacheMentionUserNames(msgs);
        await this._hydrateSocketStatuses(msgs);
        return msgs.map(m => {
            const isSystem = !!m.IsSystemMessage__c;
            const mentionedIds = m.MentionedUserIds__c
                ? m.MentionedUserIds__c.split(';')
                : [];
            const senderId = this._resolveSenderId(m);
            const isMentioned = !isSystem && mentionedIds.some(id => this._isCurrentUser(id));
            const attachments = this._resolveMessageAttachments(m, attachmentsByMessageId);
            const hasAttachment = attachments.length > 0;
            const socketStatus = this._resolveSocketStatus(senderId, m?.Thread__c);
            const showPresenceStatus = this._hasVisiblePresenceStatus(socketStatus);
            const d = m.SentAt__c ? new Date(m.SentAt__c) : null;
            const systemFormattedTime = d
                ? `${d.toLocaleDateString('pt-BR')} ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`
                : '';
            return {
                ...m,
                senderId,
                isSystemMessage: isSystem,
                systemFormattedTime,
                senderName:    this._resolveSenderName(m),
                senderPhoto:   this._resolveSenderPhoto(m),
                socketStatus,
                showPresenceStatus,
                socketStatusLabel: showPresenceStatus ? this._socketStatusLabel(socketStatus) : '',
                presenceDotClass: showPresenceStatus
                    ? `comm-msg__presence-dot comm-msg__presence-dot--${socketStatus}`
                    : '',
                formattedTime: m.SentAt__c ? new Date(m.SentAt__c).toLocaleString('pt-BR') : '',
                hasAttachment,
                attachments,
                attachmentDocumentId: hasAttachment ? attachments[0].contentDocumentId : null,
                bubbleClass:   isSystem ? '' : this._buildBubbleClass({ ...m, senderId }, isMentioned),
                isMentionedMe: isMentioned,
                _highlighted:  false
            };
        });
    }

    async _loadMessageAttachments(messages) {
        const messageIds = (messages || [])
            .filter(message => !message?.IsSystemMessage__c)
            .map(message => message?.Id)
            .filter(messageId => !!messageId);
        if (!messageIds.length) return {};

        try {
            const rows = await getMessageAttachments({ messageIds });
            const map = {};
            (rows || []).forEach(row => {
                const messageId = String(row?.messageId || '').trim();
                const contentDocumentId = String(row?.contentDocumentId || '').trim();
                if (!messageId || !contentDocumentId) return;
                if (!map[messageId]) map[messageId] = [];
                map[messageId].push({
                    contentDocumentId,
                    fileName: String(row?.fileName || '').trim() || 'arquivo'
                });
            });
            return map;
        } catch (error) {
            return {};
        }
    }

    _resolveMessageAttachments(message, attachmentsByMessageId) {
        const messageId = String(message?.Id || '').trim();
        const serverAttachments = messageId ? (attachmentsByMessageId?.[messageId] || []) : [];
        if (serverAttachments.length > 0) return serverAttachments;

        const legacyId = String(message?.ContentDocumentId__c || '').trim();
        if (!legacyId) return [];
        return [{
            contentDocumentId: legacyId,
            fileName: 'arquivo'
        }];
    }

    async _refreshThreadPresenceContext() {
        await this._loadThreadHistoryParticipants();
        await this._hydratePresenceOverrides({ bypassTtl: true });
        await this._hydrateSocketStatuses([]);
    }

    async _loadThreadHistoryParticipants() {
        if (!this.threadId && !this.isMultiThreadMode) return [];
        try {
            const ids = this.isMultiThreadMode
                ? await getThreadHistoryParticipantIdsAcrossThreads({ threadIds: this._threadIds })
                : await getThreadHistoryParticipantIds({ threadId: this.threadId });
            const unique = [...new Set(
                (ids || [])
                    .map(id => String(id || '').trim())
                    .filter(Boolean)
            )];
            this._threadHistoryParticipantIds = unique;
            return unique;
        } catch (e) {
            return this._threadHistoryParticipantIds || [];
        }
    }

    _normalizeThreadIds(value) {
        if (!Array.isArray(value)) return [];
        const unique = [...new Set(value.filter(Boolean).map(id => String(id).trim()).filter(Boolean))];
        return unique;
    }

    get isMultiThreadMode() {
        return Array.isArray(this._threadIds) && this._threadIds.length > 0;
    }

    _parseMentionUserIds(serialized) {
        if (!serialized) return [];
        return String(serialized)
            .split(';')
            .map(id => String(id || '').trim())
            .filter(Boolean);
    }

    async _cacheMentionUserNames(msgs) {
        const allMentionIds = [...new Set(
            (msgs || [])
                .flatMap(msg => this._parseMentionUserIds(msg?.MentionedUserIds__c))
        )];
        if (allMentionIds.length === 0) return;

        const missingIds = allMentionIds.filter(id => {
            const key = this._normalizeId(id);
            return key && !this._mentionUserNameById[key];
        });
        if (missingIds.length === 0) return;

        try {
            const namesById = await getMentionUserNames({ userIds: missingIds });
            const next = { ...this._mentionUserNameById };
            Object.entries(namesById || {}).forEach(([id, name]) => {
                const key = this._normalizeId(id);
                if (key && name) next[key] = name;
            });
            this._mentionUserNameById = next;
        } catch (e) {
            // Ignore mention-name lookup failures; message text remains plain.
        }
    }

    async handleAttachmentClick(event) {
        event.preventDefault();
        const contentDocumentId = event.currentTarget?.dataset?.contentDocumentId;
        const messageId = event.currentTarget?.dataset?.messageId;
        const threadId = event.currentTarget?.dataset?.threadId || this.threadId;
        if (!contentDocumentId) return;
        try {
            const attachment = await getAttachmentFile({
                contentDocumentId,
                contentVersionId: null,
                threadId,
                messageId,
                opportunityId: null
            });
            this._openAttachmentFromBase64(attachment);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Failed to open attachment', error);
        }
    }

    _openAttachmentFromBase64(attachment) {
        if (!attachment?.base64Data) return;
        const binary = atob(attachment.base64Data);
        const bytes = this._binaryToBytes(binary);
        const mimeType = this._resolveMimeType(attachment.contentType, attachment.fileExtension);
        const blob = new Blob([bytes], { type: mimeType });
        const blobUrl = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = blobUrl;
        anchor.target = '_blank';
        anchor.rel = 'noopener';
        anchor.download = attachment.fileName || 'arquivo';
        anchor.click();
        setTimeout(() => URL.revokeObjectURL(blobUrl), 60000);
    }

    _binaryToBytes(binaryValue) {
        const size = binaryValue.length;
        const buffer = new Uint8Array(size);
        for (let i = 0; i < size; i += 1) {
            buffer[i] = binaryValue.charCodeAt(i);
        }
        return buffer;
    }

    _resolveMimeType(contentType, fileExtension) {
        const ext = String(fileExtension || '').toLowerCase();
        const map = {
            pdf: 'application/pdf',
            png: 'image/png',
            jpg: 'image/jpeg',
            jpeg: 'image/jpeg',
            gif: 'image/gif',
            txt: 'text/plain',
            csv: 'text/csv',
            doc: 'application/msword',
            docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            xls: 'application/vnd.ms-excel',
            xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ppt: 'application/vnd.ms-powerpoint',
            pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            zip: 'application/zip'
        };
        if (map[ext]) return map[ext];
        const normalized = String(contentType || '').toLowerCase();
        return normalized.includes('/') ? normalized : 'application/octet-stream';
    }

    _buildBubbleClass(msg, isMentioned) {
        const isMine = this._isCurrentUser(msg.senderId || msg.Sender__c);
        const classes = ['comm-msg', isMine ? 'comm-msg--mine' : 'comm-msg--theirs'];
        if (isMentioned) classes.push('comm-msg--mentioned');
        return classes.join(' ');
    }

    _resolveSenderId(msg) {
        return msg?.Sender__c || msg?.CreatedById || null;
    }

    _resolveSenderName(msg) {
        return msg?.Sender__r?.Name || msg?.CreatedBy?.Name || 'Desconhecido';
    }

    _resolveSenderPhoto(msg) {
        if (msg?.IsSystemMessage__c || msg?.isSystemMessage) {
            return SYSTEM_AVATAR || DEFAULT_AVATAR_URL;
        }
        return msg?.Sender__r?.SmallPhotoUrl
            || msg?.CreatedBy?.SmallPhotoUrl
            || DEFAULT_AVATAR_URL;
    }

    handleAvatarError(event) {
        const img = event?.target;
        if (!img) return;
        if (img.dataset.fallbackApplied === 'true') return;
        img.dataset.fallbackApplied = 'true';
        img.src = DEFAULT_AVATAR_URL;
    }

    _isCurrentUser(userId) {
        const currentId18 = this._normalizeId18(this._currentUserId);
        const comparedId18 = this._normalizeId18(userId);
        if (currentId18 && comparedId18) {
            return currentId18 === comparedId18;
        }
        const currentId = this._normalizeId(this._currentUserId);
        const comparedId = this._normalizeId(userId);
        return !!currentId && !!comparedId && currentId === comparedId;
    }

    _normalizeId(value) {
        const raw = String(value || '').trim();
        return raw ? raw.substring(0, 15).toUpperCase() : '';
    }

    _normalizeId18(value) {
        const raw = String(value || '').trim();
        return raw.length === 18 ? raw : '';
    }

    _buildPresenceUserIdCandidates(value) {
        const rawId = String(value || '').trim();
        const caseSensitiveId18 = this._normalizeId18(rawId);
        const normalizedId = this._normalizeId(rawId);
        const candidates = caseSensitiveId18
            ? [caseSensitiveId18]
            : [rawId, normalizedId].filter(Boolean);
        return [...new Set(candidates)];
    }

    _initSocketListeners() {
        if (isSocketConnected()) this._socketStatus = 'online';
        this._socketUnsubscribes.push(
            onSocket('connect', () => {
                this._socketStatus = 'online';
                this._hydrateSocketStatuses(this.messages)
                    .then(() => this._refreshPresenceStates())
                    .catch(() => this._refreshPresenceStates());
            }),
            onSocket('disconnect', () => {
                this._socketStatus = 'offline';
                this._peerStatusMap = {};
                this._refreshPresenceStates();
            })
        );
    }

    async _hydrateSocketStatuses(msgs) {
        if (!isSocketConnected()) return;
        const peerIds = [...new Set([
            ...((this._threadHistoryParticipantIds || [])
                .flatMap(id => this._buildPresenceUserIdCandidates(id))),
            ...((msgs || [])
                .flatMap(msg => this._buildPresenceUserIdCandidates(this._resolveSenderId(msg))))
        ])].filter(id => !this._isCurrentUser(id));
        if (peerIds.length === 0) return;

        try {
            const statuses = await getUsersConnectionStatus(peerIds);
            if (!statuses) return;
            const map = { ...this._peerStatusMap };
            const entries = this._extractPresenceEntries(statuses);
            entries.forEach(entry => {
                const key = this._resolvePresenceUserKey(entry);
                if (!key) return;
                const status = this._resolvePresenceConnectionState(entry, true) ? 'online' : 'offline';
                map[key] = status;
                const rawUserId = String(entry?.userId || entry?.user_id || entry?.id || entry?.Id || '').trim();
                const key18 = this._normalizeId18(rawUserId);
                const key15 = this._normalizeId(rawUserId);
                if (key18) map[key18] = status;
                if (key15) map[key15] = status;
            });
            this._peerStatusMap = map;
        } catch (e) {
            // Keep existing map when socket lookup fails.
        }
    }

    _resolveSocketStatus(senderId, threadId = null) {
        const overrideStatus = this._resolvePresenceOverrideStatus(senderId, threadId);
        if (this._isBrokerPresenceRestrictedView()) {
            return (overrideStatus === 'online' || overrideStatus === 'offline')
                ? overrideStatus
                : null;
        }
        if (overrideStatus) return overrideStatus;
        if (!senderId) return 'offline';
        if (this._isCurrentUser(senderId)) return this._socketStatus;
        const key15 = this._normalizeId(senderId);
        const key18 = this._normalizeId18(senderId);
        return this._peerStatusMap[key18]
            || this._peerStatusMap[key15]
            || 'offline';
    }

    _socketStatusLabel(status) {
        const map = { online: 'Online', offline: 'Offline', connecting: 'Conectando...' };
        return map[status] || 'Offline';
    }

    _refreshPresenceStates() {
        if (!this.messages || this.messages.length === 0) return;
        this.messages = this.messages.map(msg => {
            if (msg.isSystemMessage) return msg;
            const senderId = msg.senderId || this._resolveSenderId(msg);
            const socketStatus = this._resolveSocketStatus(senderId, msg?.Thread__c);
            const showPresenceStatus = this._hasVisiblePresenceStatus(socketStatus);
            return {
                ...msg,
                senderId,
                socketStatus,
                showPresenceStatus,
                socketStatusLabel: showPresenceStatus ? this._socketStatusLabel(socketStatus) : '',
                presenceDotClass: showPresenceStatus
                    ? `comm-msg__presence-dot comm-msg__presence-dot--${socketStatus}`
                    : ''
            };
        });
    }

    _hasVisiblePresenceStatus(status) {
        return status === 'online' || status === 'offline' || status === 'connecting';
    }

    _isBrokerPresenceRestrictedView() {
        return !this._isSalesforcePlatformUser && this._isBrokerCommunityContext();
    }

    _isBrokerCommunityContext() {
        const pathname = (window.location?.pathname || '').toLowerCase();
        const hostname = (window.location?.hostname || '').toLowerCase();
        return hostname.includes('.my.site.com')
            || pathname.includes('/corretores')
            || pathname.includes('/s/')
            || pathname.includes('/kanban');
    }

    _resolvePresenceUserKey(entry) {
        if (!entry) return '';
        const candidates = [
            entry.userId,
            entry.user_id,
            entry.id,
            entry.Id,
            entry.user,
            entry.sfUserId,
            entry.sf_user_id,
            entry.salesforceId,
            entry.salesforce_id,
            entry.participantId,
            entry.participant_id,
            entry.contactId,
            entry.contact_id,
            entry.username,
            entry.login
        ];
        for (const candidate of candidates) {
            const normalized18 = this._normalizeId18(candidate);
            if (normalized18) return normalized18;
        }
        for (const candidate of candidates) {
            const normalized = this._normalizeId(candidate);
            if (normalized) return normalized;
        }
        return '';
    }

    _extractPresenceEntries(response) {
        if (!response) return [];
        if (Array.isArray(response)) {
            return response.map(item => {
                if (item && typeof item === 'object') return item;
                if (typeof item === 'string' || typeof item === 'number') {
                    return { userId: String(item), status: 'online' };
                }
                return null;
            }).filter(Boolean);
        }
        if (typeof response !== 'object') return [];

        const directArrays = [
            response.users,
            response.onlineUsers,
            response.participants,
            response.connections,
            response.statuses,
            response?.data?.users,
            response?.payload?.users,
            response?.result?.users
        ].filter(Array.isArray);
        if (directArrays.length > 0) {
            return directArrays
                .flat()
                .map(item => {
                    if (item && typeof item === 'object') return item;
                    if (typeof item === 'string' || typeof item === 'number') {
                        return { userId: String(item), status: 'online' };
                    }
                    return null;
                })
                .filter(Boolean);
        }

        const entries = [];
        Object.entries(response).forEach(([key, value]) => {
            if (Array.isArray(value)) {
                if (this._isSalesforceUserId(key)) {
                    if (value.length === 0) {
                        entries.push({ userId: key, connections: 0 });
                        return;
                    }
                    value.forEach(item => {
                        if (item && typeof item === 'object') {
                            if (this._resolvePresenceUserKey(item)) {
                                entries.push(item);
                                return;
                            }
                            entries.push({ ...item, userId: key, connections: value.length });
                            return;
                        }
                        entries.push({
                            userId: key,
                            socketId: String(item || ''),
                            connections: value.length,
                            status: 'online'
                        });
                    });
                    return;
                }
                value.forEach(item => {
                    if (item && typeof item === 'object') entries.push(item);
                });
                return;
            }
            if (value && typeof value === 'object') {
                if (this._resolvePresenceUserKey(value)) entries.push(value);
                else if (this._isSalesforceUserId(key)) entries.push({ ...value, userId: key });
                return;
            }
            if (this._isSalesforceUserId(key)) entries.push({ userId: key, status: value });
        });
        return entries;
    }

    _isSalesforceUserId(value) {
        return /^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$/.test(String(value || '').trim());
    }

    _resolvePresenceConnectionState(value, assumeOnlineWhenNoSignal = false) {
        if (typeof value === 'boolean') return value;
        if (typeof value === 'number') return value > 0;
        if (typeof value === 'string') return this._isOnlinePresenceKeyword(value);
        if (!value || typeof value !== 'object') return false;

        const hasExplicitSignal =
            (typeof value.connections === 'number') ||
            (typeof value.connectionCount === 'number') ||
            (typeof value.connected === 'boolean') ||
            (typeof value.isOnline === 'boolean') ||
            (typeof value.online === 'boolean') ||
            (typeof value.status === 'string') ||
            (typeof value.connectionStatus === 'string') ||
            (typeof value.state === 'string') ||
            (typeof value.socketStatus === 'string');

        if (typeof value.connections === 'number') return value.connections > 0;
        if (typeof value.connectionCount === 'number') return value.connectionCount > 0;
        if (typeof value.connected === 'boolean') return value.connected;
        if (typeof value.isOnline === 'boolean') return value.isOnline;
        if (typeof value.online === 'boolean') return value.online;
        if (this._isOnlinePresenceKeyword(value.status)) return true;
        if (this._isOnlinePresenceKeyword(value.connectionStatus)) return true;
        if (this._isOnlinePresenceKeyword(value.state)) return true;
        if (this._isOnlinePresenceKeyword(value.socketStatus)) return true;
        if (value.socketId || value.socket_id || value.sid) return true;
        if (assumeOnlineWhenNoSignal && !hasExplicitSignal) return true;
        return false;
    }

    _isOnlinePresenceKeyword(value) {
        const normalized = String(value || '').toLowerCase();
        return ['online', 'connected', 'active', 'available', 'true', '1'].includes(normalized);
    }

    async _hydratePresenceOverrides({ bypassTtl = false } = {}) {
        const now = Date.now();
        if (!bypassTtl && (now - this._presenceOverrideLastFetchAt) < this._PRESENCE_OVERRIDE_POLL_TTL_MS) {
            return;
        }
        const threadIds = this._collectThreadIdsForPresenceOverride();
        if (threadIds.length === 0) {
            this._presenceOverrideByThreadAndUser = {};
            return;
        }
        try {
            const overrides = await getThreadPresenceOverrides({ threadIds });
            this._presenceOverrideByThreadAndUser = this._buildPresenceOverrideMap(overrides);
            this._presenceOverrideLastFetchAt = Date.now();
        } catch (error) {
            this._presenceOverrideByThreadAndUser = {};
        }
    }

    _collectThreadIdsForPresenceOverride() {
        const ids = this.isMultiThreadMode ? this._threadIds : [this.threadId];
        return [...new Set(
            (ids || [])
                .map(id => String(id || '').trim())
                .filter(Boolean)
        )];
    }

    _buildPresenceOverrideMap(overrides) {
        const map = {};
        (overrides || []).forEach(override => {
            const status = String(override?.status || '').toLowerCase();
            const key = this._buildPresenceOverrideKey(override?.userId, override?.threadId);
            if (!key || (status !== 'online' && status !== 'offline')) return;
            map[key] = status;
        });
        return map;
    }

    _buildPresenceOverrideKey(userId, threadId) {
        const normalizedUserId = this._normalizeId(userId);
        const normalizedThreadId = String(threadId || '').trim().toUpperCase();
        if (!normalizedUserId || !normalizedThreadId) return '';
        return `${normalizedThreadId}:${normalizedUserId}`;
    }

    _resolvePresenceOverrideStatus(senderId, threadId) {
        const effectiveThreadId = threadId || this.threadId;
        const key = this._buildPresenceOverrideKey(senderId, effectiveThreadId);
        if (!key) return null;
        return this._presenceOverrideByThreadAndUser?.[key] || null;
    }

    _updateLastTimestamp() {
        if (this.messages.length > 0) {
            const last = this.messages[this.messages.length - 1];
            this._lastTimestamp = last.SentAt__c;
            const itemId = last.Id || last.ExternalId__c;
            const source = last.Id ? 'Message' : 'FeedItem';
            if (itemId && last.SentAt__c) {
                this._pollCursor = JSON.stringify({ timestamp: last.SentAt__c, source, itemId });
            }
        } else if (this._pollCursor === null) {
            this._pollCursor = '';
        }
    }

    _buildUserRecordUrl(userId) {
        const id = String(userId || '').trim();
        if (!id) return '#';
        return this._isExperienceRuntime()
            ? `/s/detail/${id}`
            : `/lightning/r/User/${id}/view`;
    }

    _escapeHtml(text) {
        return String(text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    _buildMessageBodyHtml(msg) {
        const rawBody = String(msg?.Body__c || '');
        const mentionIds = this._parseMentionUserIds(msg?.MentionedUserIds__c);
        if (!rawBody || mentionIds.length === 0) return this._escapeHtml(rawBody);

        const mentionItems = [];
        const seenTokens = new Set();
        mentionIds.forEach(userId => {
            const key = this._normalizeId(userId);
            const name = key ? this._mentionUserNameById[key] : null;
            if (!name) return;
            const token = `@${name}`;
            if (seenTokens.has(token)) return;
            seenTokens.add(token);
            mentionItems.push({ userId, name, token });
        });
        if (mentionItems.length === 0) return this._escapeHtml(rawBody);

        mentionItems.sort((a, b) => b.token.length - a.token.length);

        let maskedBody = rawBody;
        const placeholders = [];
        mentionItems.forEach((item, index) => {
            if (!maskedBody.includes(item.token)) return;
            const placeholder = `__COMM_MENTION_${index}__`;
            maskedBody = maskedBody.split(item.token).join(placeholder);
            placeholders.push({
                placeholder,
                html: `<a class="comm-msg__mention-link" href="${this._buildUserRecordUrl(item.userId)}" target="_blank" rel="noopener">@${this._escapeHtml(item.name)}</a>`
            });
        });

        let html = this._escapeHtml(maskedBody);
        placeholders.forEach(item => {
            html = html.split(item.placeholder).join(item.html);
        });

        return html;
    }

    _renderMessageBodies() {
        this.messages.forEach(msg => {
            if (!msg.Body__c) return;
            const el = this.template.querySelector(`p[data-id="${msg.Id}"]`);
            if (el) {
                // eslint-disable-next-line @lwc/lwc/no-inner-html
                el.innerHTML = this._buildMessageBodyHtml(msg);
            }
        });
    }

    _applyHighlight(messageId) {
        this._expandReplyAncestors(messageId);
        // Remove previous highlights
        this.template.querySelectorAll('.comm-msg--highlighted').forEach(el => {
            el.classList.remove('comm-msg--highlighted');
        });
        const el = this.template.querySelector(`[data-message-id="${messageId}"]`);
        if (el) {
            el.classList.add('comm-msg--highlighted');
        }
    }

    get isEmpty() {
        return !this.isLoadingMore
            && !this.isLoadingMessages
            && this.timelineMessages.length === 0;
    }

    _syncReplyCollapseState() {
        this._derivedParentMessageById = this._buildDerivedParentMessageLookup(this.messages);
        const repliesByParent = this._buildRepliesByParentId(this.messages);
        const parentsWithReplies = new Set(Object.keys(repliesByParent));
        const currentCollapsed = new Set(this.collapsedReplyParentIds || []);
        const nextCollapsed = new Set();

        currentCollapsed.forEach(parentId => {
            if (parentsWithReplies.has(parentId)) {
                nextCollapsed.add(parentId);
            }
        });

        parentsWithReplies.forEach(parentId => {
            if (!currentCollapsed.has(parentId)) {
                nextCollapsed.add(parentId);
            }
        });

        this.collapsedReplyParentIds = [...nextCollapsed];
        this._parentMessageById = this._buildParentMessageLookup(this.messages);
    }

    _buildParentMessageLookup(messages) {
        return (messages || []).reduce((acc, msg) => {
            const effectiveParentId = this._resolveEffectiveParentMessageId(msg);
            if (msg?.Id && effectiveParentId) {
                acc[msg.Id] = effectiveParentId;
            }
            return acc;
        }, {});
    }

    _buildDerivedParentMessageLookup(messages) {
        const map = {};
        let lastMentionMessageId = null;

        (messages || []).forEach(msg => {
            if (!msg || msg.isSystemMessage) return;

            if (!msg.ParentMessage__c && msg.HasMention__c) {
                lastMentionMessageId = msg.Id;
                return;
            }

            const shouldDeriveParent =
                !msg.ParentMessage__c &&
                !!msg.SourceThreadId__c &&
                !msg.HasMention__c &&
                !!lastMentionMessageId;

            if (shouldDeriveParent) {
                map[msg.Id] = lastMentionMessageId;
            }
        });

        return map;
    }

    _resolveEffectiveParentMessageId(msg) {
        if (!msg) return null;
        return msg.ParentMessage__c || this._derivedParentMessageById?.[msg.Id] || null;
    }

    _buildRepliesByParentId(messages) {
        return (messages || [])
            .filter(msg => !!this._resolveEffectiveParentMessageId(msg) && !msg.isSystemMessage)
            .reduce((acc, msg) => {
                const parentId = this._resolveEffectiveParentMessageId(msg);
                if (!acc[parentId]) acc[parentId] = [];
                acc[parentId].push(msg);
                return acc;
            }, {});
    }

    _expandReplyAncestors(messageId) {
        if (!messageId) return;
        const collapsedSet = new Set(this.collapsedReplyParentIds || []);
        let changed = false;
        let current = messageId;

        while (this._parentMessageById[current]) {
            const parentId = this._parentMessageById[current];
            if (collapsedSet.has(parentId)) {
                collapsedSet.delete(parentId);
                changed = true;
            }
            current = parentId;
        }

        if (changed) this.collapsedReplyParentIds = [...collapsedSet];
    }

    get timelineMessages() {
        const repliesByParent = this._buildRepliesByParentId(this.messages);
        const collapsedSet = new Set(this.collapsedReplyParentIds || []);
        const messageIdSet = new Set((this.messages || []).map(msg => msg.Id));

        return (this.messages || [])
            .filter(msg => {
                const parentId = this._resolveEffectiveParentMessageId(msg);
                return !parentId || !messageIdSet.has(parentId);
            })
            .map(msg => {
                const replies = repliesByParent[msg.Id] || [];
                const isRepliesCollapsed = replies.length > 0 && collapsedSet.has(msg.Id);
                return {
                    ...msg,
                    replies: isRepliesCollapsed
                        ? []
                        : replies.map(reply => ({
                            ...reply,
                            threadReplyClass: `${reply.bubbleClass || 'comm-msg comm-msg--theirs'} comm-msg--reply`
                        })),
                    hasReplies: replies.length > 0,
                    isRepliesCollapsed,
                    repliesCount: replies.length,
                    toggleRepliesLabel: isRepliesCollapsed
                        ? `Ver ${replies.length} ${replies.length === 1 ? 'resposta' : 'respostas'}`
                        : `Ocultar ${replies.length} ${replies.length === 1 ? 'resposta' : 'respostas'}`
                };
            });
    }

    get timelineClass() {
        const classes = ['comm-timeline'];
        if (this.emptyVariant) classes.push(`comm-timeline--${this.emptyVariant}`);
        if (this.isEmpty) classes.push('comm-timeline--empty');
        return classes.join(' ');
    }

    get emptyIconName() {
        return this.emptyVariant === 'floating'
            ? 'utility:open_folder'
            : 'utility:chat';
    }

    get emptyText() {
        return this.emptyVariant === 'floating'
            ? 'Sem mensagens anteriores. Inicie uma conversa.'
            : 'Nenhuma mensagem ainda. Inicie a conversa!';
    }

    _isExperienceRuntime() {
        const pathname = (window.location?.pathname || '').toLowerCase();
        const hostname = (window.location?.hostname || '').toLowerCase();
        if (pathname.includes('/s/')) return true;
        if (hostname.includes('live-preview')) return true;
        if (hostname.includes('.my.site.com')) return true;
        if (hostname.includes('.site.com')) return true;

        const firstSegment = pathname.split('/').filter(Boolean)[0] || '';
        const reserved = new Set(['s', 'lightning', 'one', 'apex', 'sfc']);
        return !!firstSegment && !reserved.has(firstSegment);
    }
}