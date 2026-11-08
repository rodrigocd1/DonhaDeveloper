import { LightningElement, api } from 'lwc';
import CommunicatorBroadcastImagePreviewModal from 'c/communicatorBroadcastImagePreviewModal';

export default class CommunicatorBroadcastImagePreviewModalOpener extends LightningElement {
    @api
    open(options) {
        return CommunicatorBroadcastImagePreviewModal.open({
            size: 'large',
            ...options
        });
    }
}