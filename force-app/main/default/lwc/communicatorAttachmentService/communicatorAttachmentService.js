const PREVIEWABLE_EXTENSIONS = new Set(['jpeg', 'jpg', 'pdf', 'png']);

export function isPreviewableAttachment(fileExtension) {
	return PREVIEWABLE_EXTENSIONS.has(
		String(fileExtension || '')
			.trim()
			.toLowerCase()
	);
}

export function resolveAttachmentMimeType(contentType, fileExtension) {
	const extension = String(fileExtension || '')
		.trim()
		.toLowerCase();
	const mimeTypeByExtension = {
		cls: 'text/plain',
		csv: 'text/csv',
		doc: 'application/msword',
		docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
		gif: 'image/gif',
		jpeg: 'image/jpeg',
		jpg: 'image/jpeg',
		pdf: 'application/pdf',
		png: 'image/png',
		ppt: 'application/vnd.ms-powerpoint',
		pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
		txt: 'text/plain',
		xls: 'application/vnd.ms-excel',
		xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
		zip: 'application/zip'
	};

	if (mimeTypeByExtension[extension]) return mimeTypeByExtension[extension];

	const normalizedContentType = String(contentType || '')
		.trim()
		.toLowerCase();
	return normalizedContentType.includes('/') ? normalizedContentType : 'application/octet-stream';
}

export function binaryToBytes(binaryValue) {
	const size = binaryValue.length;
	const buffer = new Uint8Array(size);
	for (let index = 0; index < size; index += 1) {
		buffer[index] = binaryValue.charCodeAt(index);
	}
	return buffer;
}

export function openAttachmentFromBase64(attachment, dependencies = {}) {
	if (!attachment?.base64Data) return false;

	const atobFn = dependencies.atobFn || atob;
	const documentRef = dependencies.documentRef || document;
	const createObjectURL = dependencies.createObjectURL || URL.createObjectURL.bind(URL);
	const revokeObjectURL = dependencies.revokeObjectURL || URL.revokeObjectURL.bind(URL);
	const setTimeoutFn = dependencies.setTimeoutFn || setTimeout;
	const fileName = String(attachment.fileName || '').trim() || 'arquivo';
	const previewable = isPreviewableAttachment(attachment.fileExtension);

	const binary = atobFn(attachment.base64Data);
	const bytes = binaryToBytes(binary);
	const mimeType = resolveAttachmentMimeType(attachment.contentType, attachment.fileExtension);
	// Locker/Aura blocks some MIME types such as text/csv in Blob.
	const blob = previewable ? new Blob([bytes], { type: mimeType }) : new Blob([bytes]);
	const blobUrl = createObjectURL(blob);
	const anchor = documentRef.createElement('a');

	anchor.href = blobUrl;
	if (previewable) {
		anchor.target = '_blank';
		anchor.rel = 'noopener';
	} else {
		anchor.download = fileName;
	}
	anchor.click();

	setTimeoutFn(() => revokeObjectURL(blobUrl), 60000);
	return true;
}