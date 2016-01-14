//
//  ChatPrivateController.swift
//  Antidote
//
//  Created by Dmytro Vorobiov on 13.01.16.
//  Copyright © 2016 dvor. All rights reserved.
//

import UIKit
import SnapKit

private struct Constants {
    static let InputViewTopOffset: CGFloat = 50.0

    static let NewMessageViewAllowedDelta: CGFloat = 20.0
    static let NewMessageViewEdgesOffset: CGFloat = 5.0
    static let NewMessageViewTopOffset: CGFloat = -15.0
    static let NewMessageViewAnimationDuration = 0.2
}

class ChatPrivateController: KeyboardNotificationController {
    private let theme: Theme
    private let chat: OCTChat
    private let submanagerChats: OCTSubmanagerChats

    private let messagesController: RBQFetchedResultsController

    private var tableView: UITableView!
    private var newMessagesView: UIView!
    private var chatInputView: ChatInputView!

    private var newMessageViewTopConstraint: Constraint!
    private var chatInputViewBottomConstraint: Constraint!

    private var didAddNewMessageInLastUpdate = false
    private var newMessagesViewVisible = false

    init(theme: Theme, chat: OCTChat, submanagerChats: OCTSubmanagerChats, submanagerObjects: OCTSubmanagerObjects) {
        self.theme = theme
        self.chat = chat
        self.submanagerChats = submanagerChats

        self.messagesController = submanagerObjects.fetchedResultsControllerForType(
                .MessageAbstract,
                predicate: NSPredicate(format: "chat.uniqueIdentifier == %@", chat.uniqueIdentifier),
                sortDescriptors: [RLMSortDescriptor(property: "dateInterval", ascending: true)])

        super.init()

        messagesController.delegate = self
        messagesController.performFetch()

        addNavigationButtons()

        edgesForExtendedLayout = .None
        hidesBottomBarWhenPushed = true

        let friend = chat.friends.lastObject() as! OCTFriend
        title = friend.nickname
    }

    required convenience init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        loadViewWithBackgroundColor(theme.colorForType(.NormalBackground))

        createTableView()
        createNewMessagesView()
        createInputView()
        installConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollToLastMessage(animated: false)
    }

    override func keyboardWillShowAnimated(keyboardFrame frame: CGRect) {
        super.keyboardWillShowAnimated(keyboardFrame: frame)

        chatInputViewBottomConstraint.updateOffset(-frame.size.height)
        view.layoutIfNeeded()

        let maxOffsetY = max(0.0, tableView.contentSize.height - tableView.frame.size.height)

        var offsetY = tableView.contentOffset.y + frame.size.height

        if offsetY > maxOffsetY {
            offsetY = maxOffsetY
        }
        tableView.contentOffset.y = offsetY
    }

    override func keyboardWillHideAnimated(keyboardFrame frame: CGRect) {
        super.keyboardWillHideAnimated(keyboardFrame: frame)

        chatInputViewBottomConstraint.updateOffset(0.0)
        view.layoutIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateInputViewMaxHeight()
    }
}

extension ChatPrivateController: UITableViewDataSource {
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let message = messagesController.objectAtIndexPath(indexPath) as! OCTMessageAbstract

        let cell = UITableViewCell()

        if message.messageText != nil {
            cell.textLabel?.text = message.messageText.text
        }

        return cell
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messagesController.numberOfRowsForSectionIndex(section)
    }
}

extension ChatPrivateController: UITableViewDelegate {
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
    }
}

extension ChatPrivateController: UIScrollViewDelegate {
    func scrollViewDidScroll(scrollView: UIScrollView) {
        guard scrollView === tableView else {
            return
        }

        let maxOffset = tableView.contentSize.height - tableView.frame.size.height - Constants.NewMessageViewAllowedDelta

        if tableView.contentOffset.y > maxOffset {
            toggleNewMessageView(show: false)
        }
    }
}

extension ChatPrivateController: RBQFetchedResultsControllerDelegate {
    func controllerWillChangeContent(controller: RBQFetchedResultsController) {
        tableView.beginUpdates()
    }

   func controllerDidChangeContent(controller: RBQFetchedResultsController) {
        ExceptionHandling.tryWithBlock({ [unowned self] in
            self.tableView.endUpdates()
        }) { [unowned self] _ in
            controller.reset()
            self.tableView.reloadData()
        }

        if didAddNewMessageInLastUpdate {
            didAddNewMessageInLastUpdate = false
            handleNewMessage()
        }
   }

    func controller(
            controller: RBQFetchedResultsController,
            didChangeObject anObject: RBQSafeRealmObject,
            atIndexPath indexPath: NSIndexPath?,
            forChangeType type: RBQFetchedResultsChangeType,
            newIndexPath: NSIndexPath?) {
        switch type {
            case .Insert:
                if newIndexPath!.row == messagesController.numberOfRowsForSectionIndex(0) {
                    didAddNewMessageInLastUpdate = true
                }

                tableView.insertRowsAtIndexPaths([newIndexPath!], withRowAnimation: .Automatic)
            case .Delete:
                tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Automatic)
            case .Move:
                tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Automatic)
                tableView.insertRowsAtIndexPaths([newIndexPath!], withRowAnimation: .Automatic)
            case .Update:
                tableView.reloadRowsAtIndexPaths([indexPath!], withRowAnimation: .None)
        }
    }
}

extension ChatPrivateController: ChatInputViewDelegate {
    func chatInputViewSendButtonPressed(view: ChatInputView) {
        do {
            try submanagerChats.sendMessageToChat(chat, text: view.text, type: .Normal)
            view.text = ""
        }
        catch {

        }
    }

    func tapOnTableView() {
        chatInputView.resignFirstResponder()
    }

    func newMessagesViewPressed() {
        scrollToLastMessage(animated: true)
    }
}

private extension ChatPrivateController {
    func addNavigationButtons() {}

    func createTableView() {
        tableView = UITableView()
        tableView.estimatedRowHeight = 44.0
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = theme.colorForType(.NormalBackground)
        tableView.separatorStyle = .None

        view.addSubview(tableView)

        tableView.registerClass(ChatListCell.self, forCellReuseIdentifier: ChatListCell.staticReuseIdentifier)

        let tapGR = UITapGestureRecognizer(target: self, action: "tapOnTableView")
        tableView.addGestureRecognizer(tapGR)
    }

    func createNewMessagesView() {
        newMessagesView = UIView()
        newMessagesView.backgroundColor = theme.colorForType(.ConnectingBackground)
        newMessagesView.layer.cornerRadius = 5.0
        newMessagesView.layer.masksToBounds = true
        newMessagesView.hidden = true
        view.addSubview(newMessagesView)

        let label = UILabel()
        label.text = String(localized: "chat_new_messages")
        label.textColor = theme.colorForType(.ConnectingText)
        label.backgroundColor = .clearColor()
        label.font = UIFont.systemFontOfSize(12.0)
        newMessagesView.addSubview(label)

        let button = UIButton()
        button.addTarget(self, action: "newMessagesViewPressed", forControlEvents: .TouchUpInside)
        newMessagesView.addSubview(button)

        label.snp_makeConstraints {
            $0.left.equalTo(newMessagesView).offset(Constants.NewMessageViewEdgesOffset)
            $0.right.equalTo(newMessagesView).offset(-Constants.NewMessageViewEdgesOffset)
            $0.top.equalTo(newMessagesView).offset(Constants.NewMessageViewEdgesOffset)
            $0.bottom.equalTo(newMessagesView).offset(-Constants.NewMessageViewEdgesOffset)
        }

        button.snp_makeConstraints {
            $0.edges.equalTo(newMessagesView)
        }
    }

    func createInputView() {
        chatInputView = ChatInputView(theme: theme)
        chatInputView.delegate = self
        view.addSubview(chatInputView)
    }

    func installConstraints() {
        tableView.snp_makeConstraints {
            $0.top.left.right.equalTo(view)
        }

        newMessagesView.snp_makeConstraints {
            $0.centerX.equalTo(tableView)
            newMessageViewTopConstraint = $0.top.equalTo(tableView.snp_bottom).constraint
        }

        chatInputView.snp_makeConstraints {
            $0.left.right.equalTo(view)
            $0.top.equalTo(tableView.snp_bottom)
            $0.top.greaterThanOrEqualTo(view).offset(Constants.InputViewTopOffset)
            chatInputViewBottomConstraint = $0.bottom.equalTo(view).constraint
        }
    }

    func updateInputViewMaxHeight() {
        chatInputView.maxHeight = chatInputView.frame.origin.y - Constants.InputViewTopOffset
    }

    func handleNewMessage() {
        let maxOffset = tableView.contentSize.height - tableView.frame.size.height - Constants.NewMessageViewAllowedDelta

        if tableView.contentOffset.y > maxOffset {
            scrollToLastMessage(animated: true)
        }
        else {
            toggleNewMessageView(show: true)
        }
    }

    func scrollToLastMessage(animated animated: Bool) {
        let count = messagesController.numberOfRowsForSectionIndex(0)

        guard count > 0 else {
            return
        }

        let path = NSIndexPath(forRow: count-1, inSection: 0)
        tableView.scrollToRowAtIndexPath(path, atScrollPosition: .Bottom, animated: animated)
    }

    func toggleNewMessageView(show show: Bool) {
        guard show != newMessagesViewVisible else {
            return
        }
        newMessagesViewVisible = show

        if show {
            newMessagesView.hidden = false
        }

        UIView.animateWithDuration(Constants.NewMessageViewAnimationDuration, animations: {
            if show {
                self.newMessageViewTopConstraint.updateOffset(Constants.NewMessageViewTopOffset - self.newMessagesView.frame.size.height)
            }
            else {
                self.newMessageViewTopConstraint.updateOffset(0.0)
            }

            self.view.layoutIfNeeded()

        }, completion: { finished in
            if !show {
                self.newMessagesView.hidden = true
            }
        })
    }
}
