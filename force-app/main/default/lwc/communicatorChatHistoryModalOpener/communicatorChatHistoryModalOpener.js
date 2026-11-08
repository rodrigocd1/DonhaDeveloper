import { LightningElement, api } from 'lwc';
import CommunicatorChatHistoryModal from 'c/communicatorChatHistoryModal';

export default class CommunicatorChatHistoryModalOpener extends LightningElement {
    @api
    open(options) {
        return CommunicatorChatHistoryModal.open(options);
    }
}