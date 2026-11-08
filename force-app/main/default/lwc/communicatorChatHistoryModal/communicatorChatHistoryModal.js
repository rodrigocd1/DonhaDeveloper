import LightningModal from 'lightning/modal';
import { api } from 'lwc';

export default class CommunicatorChatHistoryModal extends LightningModal {

    /**
     * Id of the Opportunity (or Repasse) to open directly in thread view.
     * Passed from CommunicatorChatContainer when the user clicks the history button.
     */
    @api recordId;
    @api initialThreadId = null;

    get isModalContext() { return true; }

    // ─────────────────────────────────────────
    // Navigation events from communicatorHistoryPage
    // ─────────────────────────────────────────

    handleNavigateToRecord(event) {
        const { recordId, objectType } = event.detail;
        // NavigationMixin não funciona dentro de LightningModal.
        // Passa o destino como resultado do close() para o componente
        // que abriu o modal fazer a navegação.
        this.close({ action: 'navigateToRecord', recordId, objectType: objectType || 'Opportunity' });
    }

    handleNavigateToAr(event) {
        this.close({ action: 'navigateToAr', arId: event.detail.arId });
    }
}