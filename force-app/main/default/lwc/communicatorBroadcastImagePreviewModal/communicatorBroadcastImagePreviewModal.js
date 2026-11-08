import LightningModal from 'lightning/modal';
import { api } from 'lwc';

export default class CommunicatorBroadcastImagePreviewModal extends LightningModal {
    @api src = '';
    @api fileName = 'Imagem anexada';
    @api alternativeText = 'Imagem anexada';

    get modalLabel() {
        return this.fileName || 'Imagem anexada';
    }

    handleClose() {
        this.close();
    }
}