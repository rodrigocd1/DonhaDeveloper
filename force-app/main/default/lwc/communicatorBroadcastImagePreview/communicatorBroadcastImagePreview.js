import { LightningElement, api } from 'lwc';

export default class CommunicatorBroadcastImagePreview extends LightningElement {
    _shouldFocusCloseButton = true;

    @api src = '';
    @api fileName = 'Imagem anexada';
    @api alternativeText = 'Imagem anexada';

    renderedCallback() {
        if (!this._shouldFocusCloseButton) return;
        const closeButton = this.template.querySelector('[data-close-button]');
        if (!closeButton) return;
        closeButton.focus();
        this._shouldFocusCloseButton = false;
    }

    disconnectedCallback() {
        this._shouldFocusCloseButton = true;
    }

    handleCloseClick() {
        this._dispatchClose();
    }

    handleBackdropClick() {
        this._dispatchClose();
    }

    handleSurfaceClick(event) {
        event.stopPropagation();
    }

    handleKeydown(event) {
        if (event.key !== 'Escape') return;
        event.preventDefault();
        event.stopPropagation();
        this._dispatchClose();
    }

    _dispatchClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}