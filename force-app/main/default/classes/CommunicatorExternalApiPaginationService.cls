public with sharing class CommunicatorExternalApiPaginationService {

    public static final Integer DEFAULT_PAGE_SIZE = 20;
    public static final Integer MAX_PAGE_SIZE = 200;
    public static final Integer NON_PAGINATED_SAFE_LIMIT = 500;

    public static Integer normalizePageSize(Integer pageSize) {
        Integer size = pageSize != null && pageSize > 0 ? pageSize : DEFAULT_PAGE_SIZE;
        return Math.min(size, MAX_PAGE_SIZE);
    }

    public static Integer normalizePageNumber(Integer pageNumber) {
        return pageNumber != null && pageNumber > 0 ? pageNumber : 1;
    }

    public static Integer calculateOffset(Integer pageSize, Integer pageNumber) {
        Integer normalizedPageSize = normalizePageSize(pageSize);
        Integer normalizedPageNumber = normalizePageNumber(pageNumber);
        return (normalizedPageNumber - 1) * normalizedPageSize;
    }

    public static void validateNonPaginatedLimit(Integer totalItems, String examplePath) {
        if (totalItems != null && totalItems > NON_PAGINATED_SAFE_LIMIT) {
            CommunicatorExternalApiErrorService.ApiException ex =
                CommunicatorExternalApiErrorService.unprocessable(
                    'LIMIT_EXCEEDED',
                    'A consulta retornaria ' + totalItems +
                    ' registros, quantidade acima do limite permitido para retorno sem paginacao.'
                );
            ex.action = 'Informe pageSize e pageNumber para consultar os dados paginados.';
            ex.example = examplePath;
            throw ex;
        }
    }

    public static CommunicatorExternalApiDTOs.PageDTO buildPage(
        Integer pageSize,
        Integer pageNumber,
        Integer totalItems,
        String nextCursor
    ) {
        Integer normalizedPageSize = normalizePageSize(pageSize);
        Integer normalizedPageNumber = normalizePageNumber(pageNumber);
        Integer safeTotalItems = totalItems == null || totalItems < 0 ? 0 : totalItems;
        Integer totalPages = safeTotalItems == 0
            ? 0
            : Integer.valueOf(Math.ceil((Decimal) safeTotalItems / normalizedPageSize));

        CommunicatorExternalApiDTOs.PageDTO page = new CommunicatorExternalApiDTOs.PageDTO();
        page.pageSize = normalizedPageSize;
        page.currentPage = normalizedPageNumber;
        page.totalItems = safeTotalItems;
        page.totalPages = totalPages;
        page.hasMore = safeTotalItems > (normalizedPageSize * normalizedPageNumber);
        page.nextCursor = nextCursor;
        return page;
    }
}