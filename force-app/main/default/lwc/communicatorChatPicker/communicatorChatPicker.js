import { LightningElement, api, track } from 'lwc';
import getOpportunityName               from '@salesforce/apex/CommunicatorChatController.getOpportunityName';

const RECENT_STORAGE_KEY = 'comm_recent_opportunities';
const MAX_RECENT         = 5;

export default class CommunicatorChatPicker extends LightningElement {

    /** Exibe botão de fechar no cabeçalho (modo FAB) */
    @api showCloseBtn = false;

    @track recentOpportunities = [];
    @track isLoading           = false;
    @track errorMessage        = null;

    // ─────────────────────────────────────────
    // Lifecycle
    // ─────────────────────────────────────────

    connectedCallback() {
        this._loadRecent();
    }

    // ─────────────────────────────────────────
    // Handlers
    // ─────────────────────────────────────────

    async handleOpportunitySelect(event) {
        const recordId = event.detail.recordId;
        if (!recordId) return;

        this.isLoading    = true;
        this.errorMessage = null;

        try {
            // lightning-record-picker não retorna o nome no evento —
            // buscamos via Apex com cacheable=true (sem custo de governor limit extra)
            const name = await getOpportunityName({ opportunityId: recordId });
            this._select(recordId, name || 'Oportunidade');
        } catch (err) {
            this.errorMessage = 'Erro ao carregar a Oportunidade. Tente novamente.';
            console.error('CommunicatorChatPicker.handleOpportunitySelect:', err);
        } finally {
            this.isLoading = false;
        }
    }

    handleRecentClick(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this._select(id, name);
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ─────────────────────────────────────────
    // Seleção — dispara evento para o pai
    // ─────────────────────────────────────────

    _select(recordId, name) {
        this._saveRecent(recordId, name);
        this.dispatchEvent(new CustomEvent('oppselected', {
            detail:   { recordId, name },
            bubbles:  false,
            composed: false
        }));
    }

    // ─────────────────────────────────────────
    // Recentes (localStorage)
    // ─────────────────────────────────────────

    _loadRecent() {
        try {
            const raw = localStorage.getItem(RECENT_STORAGE_KEY);
            this.recentOpportunities = raw ? JSON.parse(raw) : [];
        } catch (e) {
            this.recentOpportunities = [];
        }
    }

    _saveRecent(id, name) {
        try {
            let recent = this.recentOpportunities.filter(r => r.id !== id);
            recent.unshift({ id, name });
            if (recent.length > MAX_RECENT) recent = recent.slice(0, MAX_RECENT);
            this.recentOpportunities = recent;
            localStorage.setItem(RECENT_STORAGE_KEY, JSON.stringify(recent));
        } catch (e) { /* silencioso */ }
    }

    // ─────────────────────────────────────────
    // Computed
    // ─────────────────────────────────────────

    get hasRecent() {
        return this.recentOpportunities && this.recentOpportunities.length > 0;
    }

    get opportunityFilter() {
        return {
            criteria: [
                { fieldPath: 'IsClosed', operator: 'eq', value: false }
            ]
        };
    }
}
