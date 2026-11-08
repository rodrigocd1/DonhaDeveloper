import { LightningElement, api } from 'lwc';

const DEFAULT_AUTHOR_NAME = 'Usuario do Chatter';
const DEFAULT_ORIGIN_LABEL = 'Registro relacionado';
const INLINE_IMAGE_TAG_MARKER = '<img';

export default class CommunicatorChatterHistoryPost extends LightningElement {
    @api post;
    @api allowNavigation = false;
    @api highlighted = false;
    @api highlightedCommentId = null;

    isCommentsExpanded = false;
    hasAuthorAvatarError = false;
    commentAvatarErrorKeys = [];
    _pendingScrollFeedCommentId = null;

    get authorName() {
        return this.post && this.post.authorName
            ? this.post.authorName
            : DEFAULT_AUTHOR_NAME;
    }

    get authorPhotoUrl() {
        return this.normalizePhotoUrl(this.post && this.post.authorPhotoUrl);
    }

    get hasAuthorPhoto() {
        return !!this.authorPhotoUrl && !this.hasAuthorAvatarError;
    }

    get authorInitials() {
        return this.buildInitials(this.authorName);
    }

    get formattedCreatedDate() {
        return this.formatDateTime(this.post && this.post.createdDate);
    }

    get originLabel() {
        return this.post && this.post.originLabel
            ? this.post.originLabel
            : DEFAULT_ORIGIN_LABEL;
    }

    get postFeedItemId() {
        return this.post && this.post.feedItemId ? this.post.feedItemId : null;
    }

    get postBodySegments() {
        return this.buildContentSegments(
            this.post && this.post.bodyText,
            {
                feedItemId: this.postFeedItemId,
                feedCommentId: null,
                keyPrefix: String(this.postFeedItemId || 'post')
            }
        );
    }

    get hasBody() {
        return this.postBodySegments.length > 0;
    }

    get hasLink() {
        return this.isLinkPost && !!this.linkUrl;
    }

    get isLinkPost() {
        return this.post && this.post.feedType === 'LinkPost';
    }

    get linkUrl() {
        return this.post && this.post.linkUrl
            ? String(this.post.linkUrl).trim()
            : '';
    }

    get linkLabel() {
        const linkTitle = this.post && this.post.linkTitle
            ? String(this.post.linkTitle).trim()
            : '';
        return linkTitle || this.linkUrl;
    }

    get hasAttachments() {
        return !!(this.post && this.post.attachments && this.post.attachments.length);
    }

    get hasComments() {
        return !!(this.post && this.post.comments && this.post.comments.length);
    }

    get commentsLabel() {
        const totalComments = this.post && this.post.comments ? this.post.comments.length : 0;
        return `${totalComments} ${totalComments === 1 ? 'comentario' : 'comentarios'}`;
    }

    get visibleComments() {
        if (!this.isCommentsExpanded || !this.post || !this.post.comments) {
            return [];
        }

        const avatarErrorKeys = new Set(this.commentAvatarErrorKeys);
        return this.post.comments.map((comment) => {
            const safeAuthorName = comment && comment.authorName
                ? comment.authorName
                : DEFAULT_AUTHOR_NAME;
            const safePhotoUrl = this.normalizePhotoUrl(comment && comment.authorPhotoUrl);
            const stableKey = comment && comment.stableKey
                ? comment.stableKey
                : String(comment && comment.feedCommentId ? comment.feedCommentId : '');
            const attachments = Array.isArray(comment && comment.attachments)
                ? comment.attachments
                : [];
            const bodySegments = this.buildContentSegments(
                comment && comment.bodyText,
                {
                    feedItemId: this.postFeedItemId,
                    feedCommentId: comment && comment.feedCommentId ? comment.feedCommentId : null,
                    keyPrefix: stableKey || 'comment'
                }
            );

            return {
                ...comment,
                attachments,
                safeAuthorName,
                safePhotoUrl,
                formattedCreatedAt: this.formatDateTime(comment && comment.createdAt),
                hasAuthorPhoto: !!safePhotoUrl && !avatarErrorKeys.has(stableKey),
                authorInitials: this.buildInitials(safeAuthorName),
                hasAttachments: attachments.length > 0,
                hasBody: bodySegments.length > 0,
                bodySegments,
                bubbleClass: this.buildBubbleClass(
                    this.normalizeId(comment && comment.feedCommentId) === this.normalizedHighlightedCommentId
                )
            };
        });
    }

    get showCommentsList() {
        return this.visibleComments.length > 0;
    }

    get postBubbleClass() {
        return this.buildBubbleClass(this.highlighted);
    }

    get normalizedHighlightedCommentId() {
        return this.normalizeId(this.highlightedCommentId);
    }

    get commentsToggleLabel() {
        if (this.isCommentsExpanded) {
            return 'Ocultar comentarios';
        }
        const totalComments = this.post && this.post.comments ? this.post.comments.length : 0;
        return totalComments > 0
            ? `Exibir comentarios (${totalComments})`
            : 'Exibir comentarios';
    }

    get commentsToggleAriaExpanded() {
        return this.isCommentsExpanded ? 'true' : 'false';
    }

    handleToggleComments() {
        if (!this.hasComments) {
            return;
        }
        this.isCommentsExpanded = !this.isCommentsExpanded;
    }

    @api
    expandComments() {
        if (this.hasComments) {
            this.isCommentsExpanded = true;
        }
    }

    @api
    navigateToComment(feedCommentId) {
        const normalizedFeedCommentId = this.normalizeId(feedCommentId);
        if (!normalizedFeedCommentId || !this.hasComments) {
            return false;
        }

        this._pendingScrollFeedCommentId = normalizedFeedCommentId;
        if (!this.isCommentsExpanded) {
            this.isCommentsExpanded = true;
            return true;
        }

        return this.scrollPendingCommentIntoView();
    }

    renderedCallback() {
        this.scrollPendingCommentIntoView();
    }

    handleAuthorAvatarError() {
        this.hasAuthorAvatarError = true;
    }

    handleCommentAvatarError(event) {
        const commentKey = event.currentTarget && event.currentTarget.dataset
            ? event.currentTarget.dataset.commentKey
            : '';
        if (!commentKey || this.commentAvatarErrorKeys.includes(commentKey)) {
            return;
        }
        this.commentAvatarErrorKeys = [...this.commentAvatarErrorKeys, commentKey];
    }

    handleNavigateFile(event) {
        event.stopPropagation();
        this.dispatchNavigateFile(event.detail);
    }

    dispatchNavigateFile(detail) {
        this.dispatchEvent(new CustomEvent('navigatefile', {
            detail,
            bubbles: true,
            composed: true
        }));
    }

    scrollPendingCommentIntoView() {
        if (!this._pendingScrollFeedCommentId) {
            return false;
        }

        const commentElement = this.template.querySelector(
            `[data-feed-comment-id="${this._pendingScrollFeedCommentId}"]`
        );
        if (!commentElement) {
            return false;
        }

        commentElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
        this._pendingScrollFeedCommentId = null;
        return true;
    }

    buildBubbleClass(isHighlighted) {
        const classes = ['comm-msg__bubble'];
        if (isHighlighted) {
            classes.push('comm-msg__bubble--highlighted');
        }
        return classes.join(' ');
    }

    buildContentSegments(value, ownerContext) {
        const richTextValue = this.buildRichTextValue(value);
        if (!richTextValue) {
            return [];
        }
        return this.buildSingleRichTextSegment(richTextValue, ownerContext);
    }

    buildSingleRichTextSegment(value, ownerContext) {
        if (!value) {
            return [];
        }
        return this.normalizeSegments([
            {
                type: 'richText',
                value
            }
        ], ownerContext);
    }

    normalizeSegments(segments, ownerContext) {
        return (segments || [])
            .filter((segment) => {
                if (!segment) {
                    return false;
                }
                if (segment.type === 'richText') {
                    return segment.value !== '';
                }
                return true;
            })
            .map((segment, index) => ({
                ...segment,
                stableKey: this.buildSegmentKey(ownerContext, index, segment.type),
                isRichText: segment.type === 'richText'
            }));
    }

    buildSegmentKey(ownerContext, index, type) {
        const keyPrefix = ownerContext && ownerContext.keyPrefix
            ? String(ownerContext.keyPrefix)
            : 'segment';
        return `${keyPrefix}:${type}:${index}`;
    }

    buildRichTextValue(value) {
        const rawValue = String(value || '');
        if (!rawValue) {
            return '';
        }

        if (!rawValue.toLowerCase().includes(INLINE_IMAGE_TAG_MARKER)) {
            return rawValue;
        }

        if (typeof DOMParser === 'undefined') {
            return this.removeInlineImages(rawValue);
        }

        try {
            const parser = new DOMParser();
            const doc = parser.parseFromString(`<div>${rawValue}</div>`, 'text/html');
            const container = doc.body && doc.body.firstElementChild;
            if (!container) {
                return rawValue;
            }

            const imageContainers = [];
            Array.from(container.querySelectorAll('img')).forEach((imageNode) => {
                if (imageNode.parentElement) {
                    imageContainers.push(imageNode.parentElement);
                }
                imageNode.remove();
            });
            this.removeEmptyImageContainers(imageContainers, container);

            return container.innerHTML;
        } catch (error) {
            return this.removeInlineImages(rawValue);
        }
    }

    removeEmptyImageContainers(elements, rootElement) {
        (elements || []).forEach((element) => {
            let currentElement = element;
            while (
                currentElement &&
                currentElement !== rootElement &&
                this.isEmptyImageContainer(currentElement)
            ) {
                const parentElement = currentElement.parentElement;
                currentElement.remove();
                currentElement = parentElement;
            }
        });
    }

    isEmptyImageContainer(element) {
        if (!element || !['P', 'DIV', 'SPAN'].includes(element.tagName)) {
            return false;
        }

        const textValue = String(element.textContent || '').replace(/\u00a0/g, '').trim();
        if (textValue) {
            return false;
        }

        return Array.from(element.children || []).every((child) => child.tagName === 'BR');
    }

    removeInlineImages(value) {
        return String(value || '')
            .replace(/<img\b[^>]*>(?:<\/img>)?/gi, '')
            .replace(/<(p|div|span)\b[^>]*>(?:\s|&nbsp;|<br\s*\/?>)*<\/\1>/gi, '');
    }

    normalizePhotoUrl(value) {
        const normalizedValue = String(value || '').trim();
        return normalizedValue || '';
    }

    buildInitials(value) {
        const parts = String(value || '')
            .trim()
            .split(/\s+/)
            .filter(Boolean)
            .slice(0, 2);
        if (parts.length === 0) {
            return 'UC';
        }

        return parts
            .map((part) => part.charAt(0).toUpperCase())
            .join('');
    }

    formatDateTime(value) {
        if (!value) {
            return '';
        }

        const dateValue = value instanceof Date ? value : new Date(value);
        if (Number.isNaN(dateValue.getTime())) {
            return '';
        }

        return dateValue.toLocaleString('pt-BR', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    normalizeId(value) {
        const normalizedValue = String(value || '').trim();
        return normalizedValue || null;
    }
}