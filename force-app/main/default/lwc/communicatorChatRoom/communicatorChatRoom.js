import { LightningElement, api, track } from 'lwc';

export default class CommunicatorChatRoom extends LightningElement {

    @api threadId;
    @api opportunityName = '';
    @api unreadCount     = 0;
    /** Exibe botão fechar no cabeçalho (modo FAB) */
    @api showCloseBtn    = false;

    @track showSearch         = false;
    @track highlightMessageId = null;

    // ─────────────────────────────────────────
    // API pública — chamada pelo pai no polling
    // ─────────────────────────────────────────

    @api
    refresh() {
        this.template.querySelector('c-communicator-chat-timeline')?.refresh();
    }

    // ─────────────────────────────────────────
    // Handlers
    // ─────────────────────────────────────────

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleOpenHistory() {
        this.dispatchEvent(new CustomEvent('openhistory'));
    }

    handleToggleSearch() {
        this.showSearch = !this.showSearch;
        if (!this.showSearch) this.highlightMessageId = null;
    }

    handleNavigateToMessage(event) {
        const messageId = event.detail?.messageId;
        if (!messageId) return;
        this.showSearch = false;
        this.template.querySelector('c-communicator-chat-timeline')
            ?.navigateToMessage(messageId);
    }

    handleMessageSent() {
        this.template.querySelector('c-communicator-chat-timeline')?.scrollToBottom();
        this.dispatchEvent(new CustomEvent('messagesent'));
    }
}