@isTest
private class DAOGrupoTest {
    static testMethod void runobterGrupoComDetalhesComRelated() {
        List<Group> grupos = DAOGrupo.obterTodosGruposFiltradoPorStringParametro('XXXXXXX');
        System.assertEquals(new List<Group>(), grupos);

    }
   
    static testMethod void runobterTodosGruposFiltradoPorStringParametro() {
	    Map<Id,Group> gruposMap = DAOGrupo.obterGrupoComDetalhesComRelated();
	    System.assertNotEquals(null, gruposMap);
    }
}