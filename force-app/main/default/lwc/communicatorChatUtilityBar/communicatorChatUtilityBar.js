import { LightningElement } from 'lwc';

export default class CommunicatorChatUtilityBar extends LightningElement {
    handleRequestHistoryModal(event) {
        this._handleModalRequest({
            event,
            openerSelector: 'c-communicator-chat-history-modal-opener',
            missingMessage: 'Communicator utility modal opener is not available.'
        });
    }

    handleRequestBroadcastImagePreviewModal(event) {
        this._handleModalRequest({
            event,
            openerSelector: 'c-communicator-broadcast-image-preview-modal-opener',
            missingMessage: 'Communicator broadcast image preview modal opener is not available.'
        });
    }

    _handleModalRequest({ event, openerSelector, missingMessage }) {
        const { options, resolve, reject, markHandled } = event.detail || {};
        markHandled?.();

        const opener = this.template.querySelector(openerSelector);
        if (!opener) {
            reject?.(new Error(missingMessage));
            return;
        }

        opener.open(options)
            .then(result => resolve?.(result))
            .catch(error => reject?.(error));
    }
}