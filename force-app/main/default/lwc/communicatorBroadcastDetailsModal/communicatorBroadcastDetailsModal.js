import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import COMMUNICATOR_GROUP_OBJECT from '@salesforce/schema/CommunicatorGroup__c';
import NAME_FIELD from '@salesforce/schema/CommunicatorGroup__c.Name';
import DESCRIPTION_FIELD from '@salesforce/schema/CommunicatorGroup__c.Description__c';
import createBroadcast from '@salesforce/apex/CommunicatorChatController.createBroadcast';
import getBroadcastDetails from '@salesforce/apex/CommunicatorChatController.getBroadcastDetails';
import saveBroadcastDetails from '@salesforce/apex/CommunicatorChatController.saveBroadcastDetails';
import archiveBroadcast from '@salesforce/apex/CommunicatorChatController.archiveBroadcast';

const MODE_CREATE = 'create';
const MODE_EDIT = 'edit';
const VARIANT_COMPACT = 'compact';
const VARIANT_EXPANDED = 'expanded';
const FIELD_NAME = 'name';
const FIELD_DESCRIPTION = 'description';
const DEFAULT_NAME_MAX_LENGTH = 80;

export default class CommunicatorBroadcastDetailsModal extends LightningElement {
    _mode = MODE_EDIT;
    _broadcastId = null;
    _variant = VARIANT_EXPANDED;
    _loadSequence = 0;
    _isConnected = false;
    _initializedStateKey = null;
    _pendingStateKey = null;
    _isCommunityContext = false;

    @track name = '';
    @track description = '';
    @track audiences = [];
    @track isLoading = false;
    @track isSaving = false;
    @track errorMessage = '';
    @track showArchiveConfirm = false;
    @track nameMaxLength = DEFAULT_NAME_MAX_LENGTH;
    @track descriptionMaxLength = null;

    @wire(getObjectInfo, { objectApiName: COMMUNICATOR_GROUP_OBJECT })
    handleGroupObjectInfo({ data }) {
        if (!data?.fields) return;

        const nameLength = Number(data.fields?.[NAME_FIELD.fieldApiName]?.length);
        const descriptionLength = Number(data.fields?.[DESCRIPTION_FIELD.fieldApiName]?.length);

        if (nameLength > 0) {
            this.nameMaxLength = nameLength;
        }
        if (descriptionLength > 0) {
            this.descriptionMaxLength = descriptionLength;
        }
        this._queueValidityRefresh();
    }

    @api
    get mode() {
        return this._mode;
    }

    set mode(value) {
        const nextMode = value === MODE_CREATE ? MODE_CREATE : MODE_EDIT;
        if (nextMode === this._mode) return;
        this._mode = nextMode;
        this._initializeState().catch(() => {});
    }

    @api
    get broadcastId() {
        return this._broadcastId;
    }

    set broadcastId(value) {
        const nextValue = value ? String(value).trim() : null;
        if (nextValue === this._broadcastId) return;
        this._broadcastId = nextValue;
        this._initializeState().catch(() => {});
    }

    @api
    get variant() {
        return this._variant;
    }

    set variant(value) {
        this._variant = value === VARIANT_COMPACT ? VARIANT_COMPACT : VARIANT_EXPANDED;
    }

    @api
    get isCommunityContext() {
        return this._isCommunityContext;
    }

    set isCommunityContext(value) {
        this._isCommunityContext = value === true || value === 'true';
    }

    connectedCallback() {
        this._isConnected = true;
        this._initializeState().catch(() => {});
    }

    disconnectedCallback() {
        this._isConnected = false;
    }

    get isCreateMode() {
        return this._mode === MODE_CREATE;
    }

    get isEditMode() {
        return !this.isCreateMode;
    }

    get modalTitle() {
        return this.isCreateMode ? 'Criar grupo de comunicados' : 'Detalhes do grupo de comunicados';
    }

    get submitLabel() {
        return this.isCreateMode ? 'Criar grupo' : 'Salvar alterações';
    }

    get archiveLabel() {
        return this.showArchiveConfirm ? 'Confirmar encerramento' : 'Encerrar grupo';
    }

    get isSubmitDisabled() {
        return this.isLoading || this.isSaving;
    }

    get hasArchiveAction() {
        return this.isEditMode;
    }

    get isArchiveDisabled() {
        return this.isLoading || this.isSaving;
    }

    get overlayClass() {
        const baseClass = this._variant === VARIANT_COMPACT
            ? 'cbdm-overlay cbdm-overlay--compact'
            : 'cbdm-overlay';
        return this._isCommunityContext
            ? `${baseClass} cbdm-overlay--community`
            : baseClass;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleNameInput(event) {
        this.name = String(event.target.value || '');
        this._syncFieldValidity(event.target);
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleFieldBlur(event) {
        this._reportFieldValidity(event.target);
    }

    handleAudienceChange(event) {
        if (!Array.isArray(event?.detail?.value)) return;
        this.audiences = [...event.detail.value];
    }

    handleArchiveClick() {
        this.showArchiveConfirm = true;
    }

    handleCancelArchive() {
        this.showArchiveConfirm = false;
    }

    async handleConfirmArchive() {
        if (!this.broadcastId || this.isArchiveDisabled) return;

        this.isSaving = true;
        try {
            const archived = await archiveBroadcast({ broadcastGroupId: this.broadcastId });
            this._showToast('Sucesso', 'Grupo encerrado com sucesso.', 'success');
            this.dispatchEvent(new CustomEvent('broadcastarchived', {
                detail: { broadcast: archived }
            }));
        } catch (error) {
            const message = this._normalizeError(error) || 'Nao foi possivel encerrar o grupo.';
            this.errorMessage = message;
            this._showToast('Erro', message, 'error');
        } finally {
            this.isSaving = false;
            this.showArchiveConfirm = false;
        }
    }

    async handleSubmit() {
        if (this.isSubmitDisabled || !this._reportFormValidity()) return;

        const name = this._getNormalizedName();
        const description = this._getNormalizedDescription();
        this.isSaving = true;
        this.errorMessage = '';
        try {
            if (this.isCreateMode) {
                const created = await createBroadcast({
                    name,
                    description,
                    audiences: this.audiences
                });
                this._showToast('Sucesso', 'Grupo de comunicados criado com sucesso.', 'success');
                this.dispatchEvent(new CustomEvent('broadcastcreated', {
                    detail: { broadcast: created }
                }));
                return;
            }

            const saved = await saveBroadcastDetails({
                broadcastGroupId: this.broadcastId,
                name,
                description,
                audiences: this.audiences
            });
            this._showToast('Sucesso', 'Grupo de comunicados atualizado com sucesso.', 'success');
            this.dispatchEvent(new CustomEvent('broadcastsaved', {
                detail: { broadcast: saved }
            }));
        } catch (error) {
            const message = this._normalizeError(error) || 'Nao foi possivel salvar o comunicado.';
            this.errorMessage = message;
            this._showToast('Erro', message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async _initializeState() {
        if (!this._isConnected) return;
        await this._loadIfNeeded();
    }

    async _loadIfNeeded() {
        const stateKey = this._getStateKey();
        if (this.isCreateMode) {
            this._loadSequence += 1;
            if (stateKey === this._initializedStateKey) return;
            this._initializedStateKey = stateKey;
            this._pendingStateKey = null;
            this.isLoading = false;
            this._resetForm();
            return;
        }
        if (!this.broadcastId) {
            this._loadSequence += 1;
            this._pendingStateKey = null;
            this.isLoading = false;
            return;
        }
        if (!stateKey || stateKey === this._initializedStateKey || stateKey === this._pendingStateKey) {
            return;
        }

        const loadVersion = ++this._loadSequence;
        this._pendingStateKey = stateKey;
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const response = await getBroadcastDetails({ broadcastGroupId: this.broadcastId });
            if (loadVersion !== this._loadSequence) return;

            this.name = String(response?.broadcast?.groupName ?? '');
            this.description = String(response?.broadcast?.description ?? '');
            this.audiences = Array.isArray(response?.audiences) ? [...response.audiences] : [];
            this._initializedStateKey = stateKey;
            this._queueValidityRefresh();
        } catch (error) {
            if (loadVersion !== this._loadSequence) return;
            this.errorMessage = this._normalizeError(error) || 'Nao foi possivel carregar os detalhes do comunicado.';
        } finally {
            if (loadVersion === this._loadSequence) {
                if (this._pendingStateKey === stateKey) {
                    this._pendingStateKey = null;
                }
                this.isLoading = false;
            }
        }
    }

    _resetForm() {
        this.name = '';
        this.description = '';
        this.audiences = [];
        this.errorMessage = '';
        this.showArchiveConfirm = false;
        this._queueValidityRefresh();
    }

    _getStateKey() {
        return this.isCreateMode
            ? `${MODE_CREATE}:new`
            : this.broadcastId
                ? `${MODE_EDIT}:${this.broadcastId}`
                : null;
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _normalizeError(error) {
        return String(
            error?.body?.message
            || error?.message
            || error?.statusText
            || ''
        ).trim();
    }

    _queueValidityRefresh() {
        Promise.resolve().then(() => {
            if (!this._isConnected) return;
            this._refreshFieldValidity();
        });
    }

    _refreshFieldValidity() {
        this._syncFieldValidity(this._getFieldElement(FIELD_NAME));
        this._syncFieldValidity(this._getFieldElement(FIELD_DESCRIPTION));
    }

    _reportFormValidity() {
        const fields = [
            this._getFieldElement(FIELD_NAME),
            this._getFieldElement(FIELD_DESCRIPTION)
        ].filter(Boolean);

        let isValid = true;
        fields.forEach((field) => {
            if (!this._reportFieldValidity(field)) {
                isValid = false;
            }
        });
        return isValid;
    }

    _reportFieldValidity(field) {
        if (!field) return true;
        this._syncFieldValidity(field);
        return field.reportValidity();
    }

    _syncFieldValidity(field) {
        if (!field) return true;
        field.setCustomValidity(this._getFieldValidationMessage(field.dataset.field));
        return !field.validationMessage;
    }

    _getFieldElement(fieldName) {
        return this.template.querySelector(`[data-field="${fieldName}"]`);
    }

    _getFieldValidationMessage(fieldName) {
        if (fieldName === FIELD_NAME) {
            const normalizedName = this._getNormalizedName();
            if (!normalizedName) {
                return 'Informe o nome do comunicado.';
            }
            if (this.nameMaxLength && normalizedName.length > this.nameMaxLength) {
                return `O nome do comunicado deve ter no maximo ${this.nameMaxLength} caracteres.`;
            }
            return '';
        }

        if (fieldName === FIELD_DESCRIPTION) {
            const normalizedDescription = this._getNormalizedDescription();
            if (this.descriptionMaxLength && normalizedDescription && normalizedDescription.length > this.descriptionMaxLength) {
                return `A descricao do comunicado deve ter no maximo ${this.descriptionMaxLength} caracteres.`;
            }
        }

        return '';
    }

    _getNormalizedName() {
        return String(this.name || '').trim();
    }

    _getNormalizedDescription() {
        const normalizedDescription = String(this.description || '').trim();
        return normalizedDescription || null;
    }
}