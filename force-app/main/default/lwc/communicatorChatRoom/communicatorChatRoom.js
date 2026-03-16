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

    handleToggleSearch() {
        this.showSearch = !this.showSearch;
        if (!this.showSearch) this.highlightMessageId = null;
    }

    handleNavigateToMessage(event) {
        this.highlightMessageId = event.detail.messageId;
        this.showSearch         = false;
        this.template.querySelector('c-communicator-chat-timeline')
            ?.scrollToMessage(event.detail.messageId);
    }

    handleMessageSent() {
        this.template.querySelector('c-communicator-chat-timeline')?.scrollToBottom();
        this.dispatchEvent(new CustomEvent('messagesent'));
    }
}
