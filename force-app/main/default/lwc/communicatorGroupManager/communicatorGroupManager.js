import { LightningElement, track } from 'lwc';
import getActiveGroups from '@salesforce/apex/CommunicatorChatController.getActiveGroups';
import createGroup     from '@salesforce/apex/CommunicatorChatController.createGroup';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CommunicatorGroupManager extends LightningElement {

    @track groups         = [];
    @track newGroupName   = '';
    @track newGroupDesc   = '';
    @track isCreating     = false;
    @track isLoadingGroups = true;

    connectedCallback() {
        this._loadGroups();
    }

    handleNameChange(e) { this.newGroupName = e.detail.value; }
    handleDescChange(e) { this.newGroupDesc = e.detail.value; }

    async handleCreateGroup() {
        if (!this.newGroupName.trim()) {
            this._toast('Atenção', 'Informe o nome do grupo.', 'warning');
            return;
        }
        this.isCreating = true;
        try {
            await createGroup({ name: this.newGroupName.trim(), description: this.newGroupDesc });
            this._toast('Sucesso', `Grupo "${this.newGroupName}" criado com sucesso.`, 'success');
            this.newGroupName = '';
            this.newGroupDesc = '';
            await this._loadGroups();
        } catch (err) {
            this._toast('Erro', err.body?.message || 'Falha ao criar grupo.', 'error');
        } finally {
            this.isCreating = false;
        }
    }

    handleManageGroup(event) {
        const groupId   = event.currentTarget.dataset.id;
        const groupName = event.currentTarget.dataset.name;
        this.dispatchEvent(new CustomEvent('managegroup', {
            detail: { groupId, groupName }
        }));
    }

    async _loadGroups() {
        this.isLoadingGroups = true;
        try {
            this.groups = await getActiveGroups();
        } catch (e) {
            this.groups = [];
        } finally {
            this.isLoadingGroups = false;
        }
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get hasGroups() { return this.groups && this.groups.length > 0; }
}