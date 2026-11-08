import { LightningElement, api } from 'lwc';

export default class CommunicatorChatterHistoryAttachment extends LightningElement {
    @api attachment;
    @api feedItemId;
    @api feedCommentId;
    @api allowNavigation = false;

    get iconName() {
        return this.attachment && this.attachment.isImage
            ? 'utility:image'
            : 'utility:attach';
    }

    get typeBadgeClass() {
        const baseClassName = 'comm-chatter-attachment__badge';
        return this.attachment && this.attachment.isImage
            ? `${baseClassName} comm-chatter-attachment__badge--image`
            : `${baseClassName} comm-chatter-attachment__badge--file`;
    }

    get typeBadgeLabel() {
        return this.attachment && this.attachment.isImage ? 'Imagem' : 'Arquivo';
    }

    get actionLabel() {
        return this.attachment && this.attachment.isImage ? 'Ver imagem' : 'Ver anexo';
    }

    get showNavigateAction() {
        return this.allowNavigation === true;
    }

    get showExtension() {
        return !!(this.attachment && this.attachment.extension);
    }

    get showFileType() {
        return !!(this.attachment && this.attachment.fileType);
    }

    get showSize() {
        return Number.isFinite(this.attachment && this.attachment.size) && this.attachment.size > 0;
    }

    get formattedExtension() {
        return this.attachment && this.attachment.extension
            ? `.${String(this.attachment.extension).toLowerCase()}`
            : '';
    }

    get formattedSize() {
        const sizeInBytes = this.attachment ? Number(this.attachment.size) : 0;
        if (!Number.isFinite(sizeInBytes) || sizeInBytes <= 0) {
            return '';
        }

        if (sizeInBytes < 1024) {
            return `${sizeInBytes} B`;
        }
        if (sizeInBytes < 1024 * 1024) {
            return `${(sizeInBytes / 1024).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} KB`;
        }
        if (sizeInBytes < 1024 * 1024 * 1024) {
            return `${(sizeInBytes / (1024 * 1024)).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} MB`;
        }
        return `${(sizeInBytes / (1024 * 1024 * 1024)).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} GB`;
    }

    handleNavigateFile() {
        this.dispatchEvent(new CustomEvent('navigatefile', {
            detail: {
                contentDocumentId: this.attachment ? this.attachment.contentDocumentId : null,
                contentVersionId: this.attachment ? this.attachment.contentVersionId : null,
                title: this.attachment ? this.attachment.title : null,
                extension: this.attachment ? this.attachment.extension : null,
                fileType: this.attachment ? this.attachment.fileType : null,
                size: this.attachment ? this.attachment.size : null,
                isImage: this.attachment ? this.attachment.isImage === true : false,
                feedItemId: this.feedItemId || null,
                feedCommentId: this.feedCommentId || null
            },
            bubbles: true,
            composed: true
        }));
    }
}