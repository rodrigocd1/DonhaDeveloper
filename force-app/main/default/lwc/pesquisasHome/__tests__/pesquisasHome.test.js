import { createElement } from "@lwc/engine-dom";
import PesquisasHome from "c/pesquisasHome";

describe("c-pesquisas-home", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("exibe as três jornadas e informa a opção selecionada", () => {
    const element = createElement("c-pesquisas-home", { is: PesquisasHome });
    const handler = jest.fn();
    element.addEventListener("selecionar", handler);
    document.body.appendChild(element);

    const cards = element.shadowRoot.querySelectorAll(".journey-card");
    expect(cards).toHaveLength(3);
    cards[1].click();
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toBe("recepcao");
  });
});
