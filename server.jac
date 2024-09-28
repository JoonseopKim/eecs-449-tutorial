import:py from mtllm.llms {OpenAI}
glob llm = OpenAI(model_name='gpt-3.5-turbo');

# import:py from mtllm.llms {Ollama}
# glob llm = Ollama(model_name='llama3.2');

import:jac from rag {RagEngine}
glob rag_engine:RagEngine = RagEngine();




enum ChatType {
    RAG : 'Need to use Retrievable information in specific documents to respond' = "RAG",
    QA : 'Given context is enough for an answer' = "QA",
    MATH : 'Given mathematic calculation, do math' = "MATH"
}

node Router {
    can 'route the query to the appropriate task type'
    classify(message:'query from the user to be routed.':str) -> ChatType by llm(method="Reason", temperature=0.0);
}

walker infer {
    has message:str;
    has chat_history: list[dict];

    can init_router with `root entry {
        visit [-->](`?Router) else {
            router_node = here ++> Router();
            router_node ++> RagChat();
            router_node ++> QAChat();
            visit router_node;
        }
    }
    can route with Router entry {
        classification = here.classify(message = self.message);
        print("Classification:", classification);
        visit [-->](`?Chat)(?chat_type==classification);
    }
}

walker interact {
    has message: str;
    has session_id: str;

    can init_session with `root entry {
         visit [-->](`?Session)(?id == self.session_id) else {
            session_node = here ++> Session(id=self.session_id, chat_history=[], status=1);
            print("Session Node Created");
            visit session_node;
        }
    }
}

walker memorywipe {
    has session_id: str;
    can init_session with `root entry {
        visit [-->](`?Session)(?id == self.session_id) else {
            if session_node {
                session_node.chat_history = [];
                print("Memory wiped for session.");
            } else {
                print("Session  not found.");
            }
        }
    }
}

walker emotion {
    has message: str;
    has emotion: str;

    can analyze_emotion with `root entry{
        emotion = here.classify(message = self.message);
        print("Emotion:", emotion);
        visit [-->](`?Chat)(?chat_type==emotion);
    }
}

# walker EmotionAnalyzer {
#     has message: str;
#     has emotion: str;

#     can analyze_emotion with `root entry {
#         #// Use the LLM to classify the emotion of the message
#         here.emotion = analyze_emotion_llm(here.message);
#         #print(f"Detected emotion: {here.emotion}");

#         #// Based on the detected emotion, perform specific actions
#         if here.emotion == "negative" {
#             print("User seems upset. Provide a more empathetic response.");
#         } else if here.emotion == "positive" {
#             print("User is happy. Provide a cheerful response.");
#         } else {
#             print("Neutral tone detected.");
#         }
#     }

#     can analyze_emotion_llm with (message: str) -> 'emotion':str by llm() {
#         #// Example using LLM to analyze the sentiment or emotion of the message
#         return llm.classify(message, categories=["positive", "negative", "neutral"]);
#     }
# }





node Chat {
    has chat_type: ChatType;
}

node RagChat :Chat: {
    has chat_type: ChatType = ChatType.RAG;

    can respond with infer entry {
        can 'Respond to message using chat_history as context and agent_role as the goal of the agent'
        respond_with_llm(   message:'current message':str,
                    chat_history: 'chat history':list[dict],
                    agent_role:'role of the agent responding':str,
                    context:'retirved context from documents':list
                        ) -> 'response':str by llm();
        data = rag_engine.get_from_chroma(query=here.message);
        here.response = respond_with_llm(here.message, here.chat_history, "You are a conversation agent designed to help users with their queries based on the documents provided", data);
    }
}

node QAChat :Chat: {
    has chat_type: ChatType = ChatType.QA;

    can respond with infer entry {
        can 'Respond to message using chat_history as context and agent_role as the goal of the agent'
        respond_with_llm(   message:'current message':str,
            chat_history: 'chat history':list[dict],
            agent_role:'role of the agent responding':str
                ) -> 'response':str by llm();
        here.response = respond_with_llm(here.message, here.chat_history, agent_role="You are a conversation agent designed to help users with their queries");
    }
}


node Session {
    has id: str;
    has chat_history: list[dict];
    has status: int = 1;
    can 'Respond to message using chat_history as context and agent_role as the goal of the agent'
    llm_chat(
        message:'current message':str,
        chat_history: 'chat history':list[dict],
        agent_role:'role of the agent responding':str,
        context:'retrieved context from documents':list
    ) -> 'response':str by llm();
    can chat with interact entry {
        self.chat_history.append({"role": "user", "content": here.message});
        response = infer(message=here.message, chat_history=self.chat_history) spawn root;
        self.chat_history.append({"role": "assistant", "content": response.response});
        report {
            "response": response.response
        };
    }
}

