import { createElement } from "@lwc/engine-dom";
import PesquisasHome from "c/pesquisasHome";
import obterLojaPadrao from "@salesforce/apex/PesquisasPortalController.obterLojaPadrao";

jest.mock(
  "@salesforce/apex/PesquisasPortalController.obterLojaPadrao",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/community/basePath", () => "/pesquisas", {
  virtual: true
});

describe("c-pesquisas-home", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("exibe as três jornadas, o check-in do corretor e informa a opção selecionada", () => {
    obterLojaPadrao.mockResolvedValue({
      codigo: "LOJA-MORUMBI",
      nome: "Loja Morumbi",
      endereco: "Av. Giovanni Gronchi, 2967",
      padrao: true
    });
    const element = createElement("c-pesquisas-home", { is: PesquisasHome });
    const handler = jest.fn();
    element.addEventListener("selecionar", handler);
    document.body.appendChild(element);

    const cards = element.shadowRoot.querySelectorAll(".journey-card");
    expect(cards).toHaveLength(3);
    expect(
      element.shadowRoot.querySelector("c-pesquisas-corretor-checkin-card")
    ).not.toBeNull();
    cards[1].click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toBe("recepcao");
  });
});
